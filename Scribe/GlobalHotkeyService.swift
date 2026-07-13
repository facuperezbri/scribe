import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

/// Error de registro de un atajo de teclado global.
enum GlobalHotkeyServiceError: LocalizedError {
    case registrationFailed
    /// La app no está habilitada en Ajustes del Sistema → Privacidad y Seguridad →
    /// Monitoreo de entrada, así que `CGEvent.tapCreate` no puede instalar el tap que detecta Fn.
    case inputMonitoringPermissionDenied

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "No se pudo registrar el atajo de teclado global."
        case .inputMonitoringPermissionDenied:
            return "No se pudo activar el atajo con Fn. Revisá el permiso de Monitoreo de entrada en Ajustes del Sistema."
        }
    }
}

/// Estado observable del atajo global, para que la UI pueda explicarle al
/// usuario por qué Fn no anda sin conocer nada de `CGEventTap`/`IOHIDCheckAccess` por debajo.
enum HotkeyStatus: Equatable {
    /// Todavía no se llamó a `start`, o se llamó a `stop` después.
    case unknown
    /// El tap está instalado y recibiendo eventos: mantener Fn presionado dispara el atajo.
    case active
    /// Falta el permiso de Monitoreo de entrada, así que `CGEvent.tapCreate` no pudo instalar el
    /// tap todavía. A diferencia del monitor de `NSEvent` que este servicio reemplazó, un tap
    /// que falla al crearse no queda "instalado pero sordo": no existe en absoluto. Por eso
    /// `currentStatus()` reintenta crearlo en cada consulta (ver comentario de
    /// `LiveGlobalHotkeyService`) — así, apenas el usuario otorga el permiso, la próxima consulta
    /// (p. ej. al volver de Ajustes del Sistema) puede pasar a `.active` sin reiniciar la app.
    case inputMonitoringPermissionRequired
    /// Falló el registro por otro motivo (no relacionado con el permiso). Mensaje en español
    /// listo para mostrar.
    case failed(String)
}

/// Contrato mínimo para un servicio de atajo de teclado global: solo notifica que el atajo
/// cambió de estado (presionado o soltado), sin conocer qué debe pasar después. El mismo
/// callback se invoca en cada transición lógica que debe iniciar o detener la grabación —
/// incluyendo las que produce el modo "manos libres" (doble toque para bloquear grabando sin
/// mantener Fn presionado) — porque `DictationViewModel.handlePrimaryDictationAction` ya decide
/// qué hacer mirando solo el estado actual de la sesión (idle → arranca, recording → detiene,
/// cualquier otro caso → no hace nada). Eso alcanza para implementar tanto mantener-presionado
/// como manos libres sin que esta capa necesite exponer "abajo"/"arriba"/"bloqueado" como
/// conceptos separados en el protocolo, ni convertirse en un segundo flujo de negocio.
protocol GlobalHotkeyServicing {
    /// Arranca el servicio. `onHotkeyPressed` se invoca en el actor principal cada vez que el
    /// atajo debe arrancar o detener la grabación. Puede lanzar si el registro a nivel de sistema
    /// falla o si falta el permiso de Monitoreo de entrada; en ese último caso no queda ningún tap
    /// instalado (ver `LiveGlobalHotkeyService`), pero `currentStatus()` reintenta crearlo en cada
    /// consulta, así que si el usuario otorga el permiso más tarde el atajo arranca a funcionar
    /// sin reiniciar la app.
    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws
    /// Detiene el servicio y libera cualquier registro a nivel de sistema.
    func stop()
    /// Estado actual, recalculado en cada llamada (nunca cacheado): permite que la UI se
    /// actualice sola cuando el usuario vuelve de otorgar el permiso de Monitoreo de entrada, sin
    /// reiniciar el servicio ni la app.
    func currentStatus() -> HotkeyStatus
}

/// Modificador puro (sin una tecla "de contenido" asociada) que dispara el atajo, separado del
/// mecanismo de detección (`CGEventTap`, permiso de Monitoreo de entrada) que vive en
/// `LiveGlobalHotkeyService`. Existe como una vía de escape lista para usar si la validación en
/// hardware real (ver checklist de QA en el README) confirma que Fn no es fiable en algún
/// modelo de teclado concreto: cambiar el atajo pasaría por instanciar `LiveGlobalHotkeyService`
/// con otro `HotkeyModifierTrigger`, sin tocar el tap de eventos ni el modelo de permisos. No
/// expone una preferencia de usuario ni una UI de configuración — eso sigue fuera de alcance (ver
/// `docs/ROADMAP.md`); es solo un seam interno para un cambio de código puntual.
struct HotkeyModifierTrigger: Equatable {
    let modifierFlag: NSEvent.ModifierFlags

    static let function = HotkeyModifierTrigger(modifierFlag: .function)
    static let control = HotkeyModifierTrigger(modifierFlag: .control)

    /// `true` si `flags` incluye este modificador. `.function`/`.control` ya son máscaras
    /// independientes del dispositivo, así que no distinguen tecla izquierda de derecha (cuando la
    /// tecla en cuestión tiene ambas): cualquiera de las dos dispara el atajo.
    func isActive(in flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(modifierFlag)
    }
}

/// Máquina de estados del modo "manos libres": un doble toque rápido de Fn (presionar, soltar,
/// presionar de nuevo dentro de `doubleTapWindow`) bloquea la grabación en curso en vez de
/// requerir mantener la tecla presionada todo el tiempo; un toque simple posterior la detiene.
/// Ver `LiveGlobalHotkeyService.handleTriggerDown`/`handleTriggerUp` para la lógica de
/// transición. `internal` (no `private`) para que los tests puedan verificar la transición sin
/// depender solo de contar invocaciones del callback.
enum PushToTalkState: Equatable {
    /// Sin grabar. Un flanco de bajada (Fn presionada) arranca a grabar.
    case idle
    /// Grabando porque se mantiene Fn presionada. Soltarla programa un `pendingStopTask`
    /// diferido: si no llega un segundo flanco de bajada antes de que venza `doubleTapWindow`,
    /// ese task detiene la grabación. Si llega, es un doble toque: pasa a `.locked` sin detener.
    case recording
    /// Grabando en modo manos libres (bloqueado por un doble toque): soltar Fn ya no programa
    /// ningún detenimiento diferido. El siguiente flanco de bajada de Fn (un toque simple) es lo
    /// que la detiene.
    case locked
}

/// Callback en C para `CGEvent.tapCreate`: no puede capturar contexto, así que recupera `self`
/// desde `userInfo` (el puntero opaco que `LiveGlobalHotkeyService.attemptTapCreation` pasa como
/// `Unmanaged.passUnretained(self).toOpaque()`) y delega toda la lógica real en
/// `handleTapEvent(type:event:)`, que sí es un método normal de instancia y por eso testeable.
private let hotkeyEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let service = Unmanaged<LiveGlobalHotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handleTapEvent(type: type, event: event)
}

/// Implementación real de `GlobalHotkeyServicing`: detecta mantener Fn presionada (por defecto,
/// vía `HotkeyModifierTrigger.function`) como atajo global de "mantener presionado" (push-to-talk),
/// con un modo manos libres opcional (doble toque para bloquear grabando), igual que el atajo
/// por defecto de Whispr Flow. Ver [docs/DECISIONS.md](../docs/DECISIONS.md) para la motivación
/// completa de esta migración (de un par de monitores de `NSEvent` a un único `CGEventTap`) y de
/// las migraciones de atajo anteriores.
///
/// ## Por qué `CGEventTap` en vez de `NSEvent.addGlobalMonitorForEvents`
/// El mecanismo anterior (dos monitores de `NSEvent`, uno global y uno local) solo podía
/// *observar* eventos: no había forma de evitar que, además de disparar el atajo de Scribe, Fn
/// también disparara la función de sistema bajo Ajustes del Sistema → Teclado → "Presionar la
/// tecla 🌐 Fn para:" (cambiar la fuente de entrada, mostrar Emojis y Símbolos, iniciar Dictado) —
/// ese fue el compromiso conocido documentado en la migración anterior. Un `CGEventTap` instalado
/// en `.cghidEventTap` (el punto más bajo posible, antes de que WindowServer distribuya el evento
/// a cualquier app o al propio sistema) sí puede: el callback devuelve el evento sin modificar
/// para dejarlo pasar, o `nil` para consumirlo por completo. Este servicio consume exactamente los
/// eventos `flagsChanged` que representan un flanco de `trigger` (Fn presionada o soltada) — los
/// mismos que ya disparaban el atajo con el mecanismo anterior — así que, mientras el tap esté
/// activo, ni el resto del sistema ni otras apps vuelven a ver esos eventos de Fn en absoluto, y
/// la función de sistema de arriba deja de dispararse sin que el usuario tenga que poner esa
/// opción en "No hacer nada" a mano. **No verificado en hardware real** (sin captura de pantalla
/// ni automation de UI disponible en este entorno): que un `CGEventTap` en `.cghidEventTap`
/// efectivamente preempte esa función de sistema es la hipótesis mejor fundamentada de la
/// investigación que motivó este cambio, no un hecho confirmado corriendo la app. Si en algún caso
/// concreto la función de sistema sigue disparándose igual, la mitigación de la migración anterior
/// (poner esa opción en "No hacer nada" en Ajustes del Sistema → Teclado) sigue siendo válida
/// como respaldo.
///
/// ## Permiso de Monitoreo de entrada (nuevo respecto a la migración anterior)
/// `CGEventTapCreate` (el `tapCreate` de abajo) requiere que la app esté habilitada en Ajustes
/// del Sistema → Privacidad y Seguridad → Monitoreo de entrada — un permiso distinto de
/// Accesibilidad (que ya no hace falta para este atajo específico, aunque `AutoPasteService`
/// sigue necesitándolo para su propio synthetic ⌘V; ver `AutoPasteService.swift`). A diferencia
/// del monitor de `NSEvent` anterior, que se creaba igual sin el permiso y simplemente no recibía
/// eventos hasta que se otorgaba, un tap sin este permiso **no se crea en absoluto**
/// (`tapCreate` devuelve `nil`): no hay "instalado pero sordo" posible acá. Por eso
/// `attemptTapCreation()` no es una llamada de una sola vez en `start()`: también la reintenta
/// `currentStatus()` en cada consulta, así que la app se autorepara apenas el usuario otorga el
/// permiso desde Ajustes del Sistema y vuelve a Scribe, sin reiniciarla — mismo comportamiento
/// visible que el permiso de Accesibilidad tenía antes, aunque el mecanismo interno sea distinto
/// (reintentar crear el tap en vez de solo re-leer un flag). El chequeo en sí usa
/// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` sin mostrar ningún diálogo nativo — el
/// diálogo lo dispara macOS solo la primera vez que `tapCreate` efectivamente lo intenta, igual de
/// "no empujado fuera de este flujo" que el chequeo de Accesibilidad que reemplaza.
///
/// ## Modo manos libres: doble toque para bloquear
/// Además de mantener-presionado (push-to-talk), un doble toque rápido de Fn (presionar, soltar,
/// presionar de nuevo dentro de `doubleTapWindow`, por defecto `NSEvent.doubleClickInterval` — la
/// misma velocidad de doble clic que el usuario ya configuró en Ajustes del Sistema, no un número
/// mágico propio) bloquea la grabación en curso: soltar la segunda vez ya no la detiene, así que
/// se puede grabar largo sin mantener la tecla presionada todo el tiempo. Un toque simple
/// posterior la detiene y arranca la transcripción. Ver `PushToTalkState` para la máquina de tres
/// estados que implementa esto, y su documentación para el detalle de cada transición.
/// **Compromiso conocido:** esperar `doubleTapWindow` antes de confirmar que un toque no fue el
/// primero de un doble toque agrega esa misma latencia a *todo* mantener-presionado normal (el
/// callback de "detener" ya no dispara en el instante exacto de soltar Fn, sino hasta
/// `doubleTapWindow` después si no llega un segundo toque). No verificado en hardware real si esa
/// latencia (típicamente unos cientos de milisegundos) resulta perceptible en uso normal.
///
/// ## `HotkeyModifierTrigger` y el puente `CGEvent` → `NSEvent`
/// La detección de flancos sigue exactamente la misma lógica que antes (comparar
/// `trigger.isActive(in:)` contra el último estado conocido), sin cambios: `handleTapEvent`
/// convierte el `CGEvent` recibido a un `NSEvent` (`NSEvent(cgEvent:)`) antes de delegar en
/// `handleFlagsChanged`, así que `HotkeyModifierTrigger`, sus tests, y el seam para volver a
/// `.control` u otro modificador no cambiaron en absoluto por esta migración.
///
/// ## Limitaciones conocidas
/// - No verificado en hardware real durante esta migración (ver limitación de arriba sobre si el
///   tap efectivamente preempta la función de sistema, y la ya conocida de migraciones previas
///   sobre variación de Fn entre modelos de teclado). Ver checklist de QA manual en el README.
/// - Si `stop()` no se llama antes de que el proceso termine, macOS libera el tap solo; no hay
///   ninguna limpieza adicional pendiente del lado de Scribe.
final class LiveGlobalHotkeyService: GlobalHotkeyServicing {
    private let trigger: HotkeyModifierTrigger
    private let doubleTapWindow: TimeInterval

    /// `trigger` por defecto es `.function`; un caller puede pasar otro `HotkeyModifierTrigger` si
    /// la validación en hardware real o de uso confirma que Fn no es viable en algún teclado o
    /// flujo de trabajo concreto (ver el comentario sobre `HotkeyModifierTrigger` más arriba).
    /// `doubleTapWindow` por defecto es `NSEvent.doubleClickInterval`; los tests lo inyectan mucho
    /// más corto para no depender de esperas reales de cientos de milisegundos.
    init(trigger: HotkeyModifierTrigger = .function, doubleTapWindow: TimeInterval = TimeInterval(NSEvent.doubleClickInterval)) {
        self.trigger = trigger
        self.doubleTapWindow = doubleTapWindow
    }

    private var onHotkeyPressed: (@MainActor () -> Void)?
    /// `CFMachPort` del tap instalado por `attemptTapCreation()`, o `nil` si nunca se pudo crear
    /// (falta el permiso de Monitoreo de entrada, o no se llamó a `start`/ya se llamó a `stop`).
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// `true` desde que `start` se llama por primera vez hasta el siguiente `stop`. Distingue
    /// "todavía no arrancó" (`.unknown`) de "arrancó, pero sin el tap creado todavía"
    /// (`.inputMonitoringPermissionRequired`) en `currentStatus()`.
    private var hasStarted = false
    /// Refleja si `trigger` está activo en el último `flagsChanged` visto, para quedarse solo con
    /// los flancos (subida/bajada) en vez de disparar el callback con cada cambio de modificador,
    /// que no siempre involucra a `trigger`.
    private var isTriggerActive = false
    /// Estado del modo manos libres. `internal` (no `private`) para que los tests puedan
    /// verificar la transición directamente, ver `PushToTalkState`.
    private(set) var pushToTalkState: PushToTalkState = .idle
    /// Detiene la grabación diferido tras soltar Fn, cancelado si llega un segundo toque dentro de
    /// `doubleTapWindow` (ver `PushToTalkState.recording`).
    private var pendingStopTask: Task<Void, Never>?

    /// Último error de registro conocido. No forma parte de `GlobalHotkeyServicing`: es una
    /// forma de que un caller que sepa que tiene un `LiveGlobalHotkeyService` pueda inspeccionar
    /// el estado sin que el protocolo cargue con ese detalle. `currentStatus()` es la vía
    /// recomendada para la UI.
    private(set) var lastRegistrationError: GlobalHotkeyServiceError?

    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws {
        self.onHotkeyPressed = onHotkeyPressed
        lastRegistrationError = nil
        hasStarted = true
        isTriggerActive = false
        pushToTalkState = .idle
        pendingStopTask?.cancel()
        pendingStopTask = nil

        guard attemptTapCreation() else {
            let error: GlobalHotkeyServiceError = hasInputMonitoringAccess ? .registrationFailed : .inputMonitoringPermissionDenied
            lastRegistrationError = error
            throw error
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
        onHotkeyPressed = nil
        hasStarted = false
        isTriggerActive = false
        pushToTalkState = .idle
        pendingStopTask?.cancel()
        pendingStopTask = nil
    }

    /// Recalculado en cada llamada: no depende de `lastRegistrationError`, que solo refleja lo
    /// que pasó en el último `start`. Si el tap todavía no existe (porque `start` no pudo crearlo
    /// por falta de permiso), reintenta crearlo acá mismo — ver el comentario sobre el permiso de
    /// Monitoreo de entrada más arriba para por qué ese reintento vive en la consulta de estado en
    /// vez de en un `start` de una sola vez.
    func currentStatus() -> HotkeyStatus {
        guard hasStarted else { return .unknown }
        guard eventTap != nil || attemptTapCreation() else {
            return hasInputMonitoringAccess
                ? .failed(GlobalHotkeyServiceError.registrationFailed.errorDescription ?? GlobalHotkeyServiceError.registrationFailed.localizedDescription)
                : .inputMonitoringPermissionRequired
        }
        return .active
    }

    private var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Crea `eventTap` si todavía no existe. Idempotente: devuelve `true` de inmediato si ya hay
    /// un tap instalado, sin crear uno segundo. `CGEvent.tapCreate` en `.cghidEventTap` devuelve
    /// `nil` sin lanzar nada si falta el permiso de Monitoreo de entrada — no hay excepción ni
    /// mensaje de error nativo que capturar acá, solo el `nil`.
    @discardableResult
    private func attemptTapCreation() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: selfPointer
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Despacha un evento recibido del tap. `internal` (no `private`) para que los tests puedan
    /// invocarlo directamente sin instalar un tap real. macOS deshabilita un tap solo si su
    /// callback tarda demasiado o el usuario lo deshabilita manualmente
    /// (`.tapDisabledByTimeout`/`.tapDisabledByUserInput`); ambos casos se resuelven
    /// reactivándolo, nunca consumiendo ese evento de control. Cualquier otro tipo de evento que
    /// no sea `flagsChanged`, o un `flagsChanged` que no representa un flanco de `trigger`, pasa
    /// sin modificar.
    func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        guard type == .flagsChanged, let nsEvent = NSEvent(cgEvent: event), handleFlagsChanged(nsEvent) else {
            return Unmanaged.passRetained(event)
        }
        return nil
    }

    /// Detecta el flanco (subida o bajada) de `trigger` dentro de `event.modifierFlags` y lo
    /// despacha a `handleTriggerDown`/`handleTriggerUp`. Devuelve `true` solo cuando el evento
    /// representa un flanco real de `trigger` — lo que `handleTapEvent` usa para decidir si debe
    /// consumir (`nil`) o dejar pasar el evento del tap. `internal` (no `private`) para que los
    /// tests puedan invocarlo directamente con eventos sintéticos construidos vía
    /// `NSEvent.keyEvent(...)`, sin depender de un teclado ni de un tap real.
    @discardableResult
    func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let isActive = trigger.isActive(in: event.modifierFlags)
        guard isActive != isTriggerActive else { return false }
        isTriggerActive = isActive

        if isActive {
            handleTriggerDown()
        } else {
            handleTriggerUp()
        }
        return true
    }

    /// Flanco de bajada (Fn presionada). Cualquier toque nuevo cancela un `pendingStopTask`
    /// pendiente del toque anterior, porque este flanco decide qué pasa a continuación:
    /// - `.idle` → arranca a grabar (toque normal).
    /// - `.recording` → este es el segundo toque de un doble toque dentro de `doubleTapWindow`:
    ///   pasa a `.locked` sin avisar al callback (ya se está grabando desde el punto de vista de
    ///   `DictationViewModel`).
    /// - `.locked` → toque simple para salir del modo manos libres: detiene y transcribe.
    private func handleTriggerDown() {
        pendingStopTask?.cancel()
        pendingStopTask = nil

        switch pushToTalkState {
        case .idle:
            pushToTalkState = .recording
            emit()
        case .recording:
            pushToTalkState = .locked
        case .locked:
            pushToTalkState = .idle
            emit()
        }
    }

    /// Flanco de bajada→arriba (Fn soltada). Solo importa mientras `pushToTalkState == .recording`
    /// (mantener-presionado en curso, todavía no bloqueado): programa un detenimiento diferido de
    /// `doubleTapWindow`, para darle tiempo a un segundo toque de convertir esto en modo manos
    /// libres antes de asumir que fue un mantener-presionado normal. El task diferido vuelve a
    /// chequear `pushToTalkState == .recording` antes de disparar — si mientras tanto llegó un
    /// segundo toque (`handleTriggerDown` ya lo canceló) o `stop()` reinició el estado, no hace
    /// nada. Soltar en `.idle` (la soltada que sigue al toque que sale de `.locked`) o en
    /// `.locked` (soltar durante manos libres) no programa nada — ver `PushToTalkState`.
    private func handleTriggerUp() {
        guard pushToTalkState == .recording else { return }

        let window = doubleTapWindow
        pendingStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(window * 1000)))
            guard let self, !Task.isCancelled, self.pushToTalkState == .recording else { return }
            self.pushToTalkState = .idle
            self.pendingStopTask = nil
            self.emit()
        }
    }

    private func emit() {
        guard let onHotkeyPressed else { return }
        Task { @MainActor in
            onHotkeyPressed()
        }
    }
}
