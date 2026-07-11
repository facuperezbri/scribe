import AppKit
import ApplicationServices
import Foundation

/// Error de registro de un atajo de teclado global.
enum GlobalHotkeyServiceError: LocalizedError {
    case registrationFailed
    /// La app no está habilitada en Ajustes del Sistema → Privacidad y Seguridad →
    /// Accesibilidad, así que el monitor de teclado global no recibe eventos todavía.
    case accessibilityPermissionDenied

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "No se pudo registrar el atajo de teclado global."
        case .accessibilityPermissionDenied:
            return "No se pudo activar el atajo con Fn + Espacio. Revisá el permiso de Accesibilidad en Ajustes del Sistema."
        }
    }
}

/// Estado observable del atajo global, para que la UI pueda explicarle al
/// usuario por qué Fn + Espacio no anda sin conocer nada de `NSEvent`/`AXIsProcessTrusted` por
/// debajo.
enum HotkeyStatus: Equatable {
    /// Todavía no se llamó a `start`, o se llamó a `stop` después.
    case unknown
    /// El monitor está instalado y la app tiene permiso de Accesibilidad: Fn + Espacio dispara el
    /// atajo.
    case active
    /// El monitor está instalado pero falta el permiso de Accesibilidad, así que no le llegan
    /// eventos todavía. Se resuelve solo (sin reiniciar la app) apenas el usuario otorga el
    /// permiso; `currentStatus()` lo refleja la próxima vez que se consulta.
    case accessibilityPermissionRequired
    /// Falló el registro por otro motivo (no relacionado con Accesibilidad). Mensaje en español
    /// listo para mostrar.
    case failed(String)
}

/// Contrato mínimo para un servicio de atajo de teclado global: solo notifica que el atajo se
/// presionó, sin conocer qué debe pasar después. `DictationViewModel.handlePrimaryDictationAction`
/// sigue siendo el único lugar que decide qué hacer (grabar o detener), así que esta capa no
/// puede convertirse en un segundo flujo de negocio.
protocol GlobalHotkeyServicing {
    /// Arranca el servicio. `onHotkeyPressed` se invoca en el actor principal cada vez que se
    /// detecta el atajo. Puede lanzar si el registro a nivel de sistema falla o si falta el
    /// permiso de Accesibilidad; en ese último caso el monitor queda instalado igual, así que si
    /// el usuario otorga el permiso más tarde el atajo arranca a funcionar sin reiniciar la app.
    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws
    /// Detiene el servicio y libera cualquier registro a nivel de sistema.
    func stop()
    /// Estado actual, recalculado en cada llamada (nunca cacheado): permite que la UI se
    /// actualice sola cuando el usuario vuelve de otorgar el permiso de Accesibilidad, sin
    /// reiniciar el servicio ni la app.
    func currentStatus() -> HotkeyStatus
}

/// Implementación real de `GlobalHotkeyServicing`: detecta Fn + Espacio como atajo global de
/// toggle. Ver `docs/DECISIONS.md` para la motivación de elegir Fn + Espacio sobre Option solo.
///
/// ## Enfoque elegido
/// Fn + Espacio combina un modificador (Fn) con una tecla "no modificadora" real (Space, keyCode
/// 49), a diferencia de Option solo. Eso descarta `RegisterEventHotKey` (Carbon) como alternativa
/// más liviana solo por simplicidad: esa API sí acepta esta combinación, pero se mantiene
/// `NSEvent.addGlobalMonitorForEvents(matching:)` para no introducir un segundo mecanismo de
/// registro de atajos en el proyecto y porque el modelo de permisos (ver abajo) es idéntico al que
/// ya usaba el monitor de Option. La detección usa `.keyDown` (en vez de `flagsChanged`, que solo
/// informa cambios de modificadores, sin contenido de tecla), chequeando `keyCode == 49` y que
/// `modifierFlags` incluya `.function`.
///
/// Se descartó Option solo porque bloquea el uso normal de Option para acentos/diacríticos del
/// teclado en español (Option+E, Option+U, etc. para á/é/í/ó/ú, ü) — Fn + Espacio no colisiona con
/// ninguna combinación de tecla muerta.
///
/// ## Por qué Fn + Espacio es detectable de forma confiable
/// La tecla Fn físicamente reasignada (Fn+flecha → Home/End, Fn+Delete → Forward Delete, Fn+F1-F12
/// → teclas de medios) es interceptada por el driver de teclado antes de llegar a las apps como
/// `modifierFlags`, así que esas combinaciones no son observables de forma confiable con esta
/// técnica. Space no es una de esas teclas reasignadas: no tiene una función de sistema ligada a
/// Fn, así que Fn + Espacio llega como un `keyDown` normal de keyCode 49 con `.function` presente
/// en `modifierFlags`, igual que cualquier otro modificador.
///
/// ## Permisos
/// Un monitor global de eventos de teclado (`flagsChanged` o `keyDown`, misma API por debajo)
/// requiere que la app esté habilitada en Ajustes del Sistema → Privacidad y Seguridad →
/// Accesibilidad; no hay un permiso adicional de "Monitoreo de entrada" involucrado porque
/// `NSEvent.addGlobalMonitorForEvents` no usa `CGEventTapCreate`/`IOHIDManager` directamente (esos
/// sí activan ese permiso separado). Sin el permiso de Accesibilidad, `addGlobalMonitorForEvents`
/// no falla ni devuelve `nil`: el token de monitor se crea igual, simplemente no le llegan eventos
/// hasta que se otorgue el permiso. Por eso `start` instala el monitor siempre (así el atajo
/// empieza a andar solo si el permiso se concede después, sin requerir reiniciar la app) y usa
/// `AXIsProcessTrusted()` (sin mostrar el diálogo nativo, para no pedir permiso fuera de este
/// flujo) únicamente para decidir si lanza `GlobalHotkeyServiceError.accessibilityPermissionDenied`
/// y para dejarlo en `lastRegistrationError`. `DictationViewModel` sigue llamando `start` con
/// `try?`, así que el throw no rompe nada más que arranque la app; `currentStatus()` es la vía
/// por la que la UI se entera de ese estado y lo vuelve a consultar sin reiniciar el servicio.
///
/// ## Local + global
/// `NSEvent.addGlobalMonitorForEvents` únicamente entrega eventos destinados a *otras* apps: en
/// cuanto Scribe pasa a ser la app activa (p. ej. porque el usuario abrió la ventana principal),
/// el sistema deja de mandarle esos eventos al monitor global y los despacha por el camino normal
/// de la app, donde nada los interceptaba — por eso Fn + Espacio dejaba de andar apenas Scribe
/// tenía el foco. `NSEvent.addLocalMonitorForEvents` cubre exactamente el caso complementario:
/// solo ve eventos mientras la app es la activa. Ambos caminos de despacho son mutuamente
/// excluyentes para un mismo evento físico (AppKit lo manda por uno u otro, nunca por los dos), así
/// que instalar los dos monitores no duplica el disparo del atajo; cada uno delega en el mismo
/// `handleKeyDown`, que sigue siendo la única lógica de detección. El monitor local no depende del
/// permiso de Accesibilidad (solo el global lo necesita), y devuelve el evento sin modificar para
/// no tragarse ninguna tecla normal que el usuario escriba dentro de Scribe.
///
/// ## Limitaciones conocidas
/// - No verificado en hardware real durante esta migración (sin captura de pantalla ni automation
///   de UI disponible en este entorno): el comportamiento de Fn en distintos modelos de teclado
///   (Magic Keyboard vs. built-in, teclados de terceros sin tecla Fn dedicada) puede variar. Ver
///   checklist de QA manual.
/// - Igual que antes con Option: si se suelta un modificador extra mientras Fn + Space sigue
///   presionado, o viceversa, puede interpretarse como una presión nueva del atajo. Caso borde
///   aceptado.
/// - Todavía no hay modo "mantener presionado" (hold-to-talk); ver el TODO en `handleKeyDown`.
final class LiveGlobalHotkeyService: GlobalHotkeyServicing {
    /// keyCode físico de la barra espaciadora, independiente de layout de teclado (no es un
    /// carácter, así que no varía con distribuciones como QWERTY en español vs. inglés).
    static let spaceKeyCode: UInt16 = 49

    private var onHotkeyPressed: (@MainActor () -> Void)?
    /// Ve el atajo cuando otra app tiene el foco (Scribe no es la app activa). Requiere permiso
    /// de Accesibilidad.
    private var globalMonitor: Any?
    /// Ve el atajo cuando Scribe mismo es la app activa (ventana principal al frente, o
    /// simplemente activada sin ventana visible). No requiere permiso de Accesibilidad: por eso
    /// `currentStatus()` sigue basando `.active`/`.accessibilityPermissionRequired` solo en
    /// `globalMonitor` + `AXIsProcessTrusted()`.
    private var localMonitor: Any?
    /// `true` desde que `start` se llama por primera vez hasta el siguiente `stop`. Distingue
    /// "todavía no arrancó" (`.unknown`) de "arrancó, pero sin permiso de Accesibilidad todavía"
    /// (`.accessibilityPermissionRequired`) en `currentStatus()`.
    private var hasStarted = false

    /// Último error de registro conocido. No forma parte de `GlobalHotkeyServicing`: es una
    /// forma de que un caller que sepa que tiene un `LiveGlobalHotkeyService` pueda inspeccionar
    /// el estado sin que el protocolo cargue con ese detalle. `currentStatus()` es la vía
    /// recomendada para la UI.
    private(set) var lastRegistrationError: GlobalHotkeyServiceError?

    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws {
        self.onHotkeyPressed = onHotkeyPressed
        lastRegistrationError = nil
        hasStarted = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event) ?? event
        }

        guard globalMonitor != nil, localMonitor != nil else {
            let error = GlobalHotkeyServiceError.registrationFailed
            lastRegistrationError = error
            throw error
        }

        guard AXIsProcessTrusted() else {
            let error = GlobalHotkeyServiceError.accessibilityPermissionDenied
            lastRegistrationError = error
            throw error
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        onHotkeyPressed = nil
        hasStarted = false
    }

    /// Recalculado en cada llamada: no depende de `lastRegistrationError`, que solo refleja lo
    /// que pasó en el último `start`. Así, si el usuario otorga el permiso de Accesibilidad
    /// después de que la app arrancó, la próxima consulta (p. ej. al volver de Ajustes del
    /// Sistema) ve `.active` sin reiniciar el monitor.
    func currentStatus() -> HotkeyStatus {
        guard hasStarted else { return .unknown }
        guard globalMonitor != nil, localMonitor != nil else {
            return .failed(GlobalHotkeyServiceError.registrationFailed.errorDescription ?? GlobalHotkeyServiceError.registrationFailed.localizedDescription)
        }
        return AXIsProcessTrusted() ? .active : .accessibilityPermissionRequired
    }

    /// Dispara el callback solo en el `keyDown` inicial de Space con `.function` presente, nunca
    /// en las repeticiones automáticas que genera el sistema mientras se mantiene una tecla
    /// presionada (`isARepeat`): a diferencia de `flagsChanged` (que no repite), `keyDown` sí lo
    /// hace, así que sin este chequeo mantener Fn + Espacio dispararía el toggle varias veces por
    /// segundo. `internal` (no `private`) para que los tests puedan invocarlo directamente con
    /// eventos sintéticos construidos vía `NSEvent.keyEvent(...)`, sin depender de un teclado real.
    ///
    /// TODO: agregar modo "mantener presionado" (hold-to-talk) como alternativa al
    /// toggle actual — probablemente distinguiendo el primer `keyDown` (ya disponible acá) de un
    /// `keyUp` posterior de Space.
    func handleKeyDown(_ event: NSEvent) {
        guard event.keyCode == Self.spaceKeyCode,
              event.modifierFlags.contains(.function),
              !event.isARepeat,
              let callback = onHotkeyPressed else { return }
        Task { @MainActor in
            callback()
        }
    }

    /// Wrapper de `handleKeyDown` para el monitor local: siempre devuelve el evento recibido sin
    /// modificar, para no tragarse ninguna tecla normal que el usuario escriba dentro de Scribe
    /// (p. ej. en el editor de la transcripción). `internal` (no `private`), igual que
    /// `handleKeyDown`, para que los tests puedan verificar el passthrough sin instalar un monitor
    /// real.
    func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        handleKeyDown(event)
        return event
    }
}
