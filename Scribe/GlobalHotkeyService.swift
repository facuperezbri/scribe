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
            return "No se pudo activar el atajo con Option. Revisá los permisos de Accesibilidad o Entrada de teclado en Ajustes del Sistema."
        }
    }
}

/// Estado observable del atajo global, para que la UI (Fase 6 de MVP3) pueda explicarle al
/// usuario por qué Option no anda sin conocer nada de `NSEvent`/`AXIsProcessTrusted` por debajo.
enum HotkeyStatus: Equatable {
    /// Todavía no se llamó a `start`, o se llamó a `stop` después.
    case unknown
    /// El monitor está instalado y la app tiene permiso de Accesibilidad: Option dispara el atajo.
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

/// Implementación real de `GlobalHotkeyServicing`: detecta la tecla Option sola (sin ningún otro
/// modificador) como atajo global de toggle (Fase 5 de MVP3).
///
/// ## Enfoque elegido
/// Option sola no es una combinación válida para `RegisterEventHotKey` (Carbon): esa API espera
/// una tecla "no modificadora" (letra, número, Space, etc.) más modificadores opcionales, no un
/// modificador solo. La señal de que Option se presiona o se suelta llega como eventos de cambio
/// de modificadores (`NSEvent.EventTypeMask.flagsChanged`, equivalente en AppKit a un evento
/// `CGEventType.flagsChanged` de un event tap de CoreGraphics/Carbon). Se eligió
/// `NSEvent.addGlobalMonitorForEvents(matching:)` en vez de instalar un `CGEventTap` a mano
/// porque:
/// - Es la envoltura de más alto nivel que AppKit ofrece para lo mismo (mismo mecanismo del
///   sistema por debajo), sin manejar directamente un `CFMachPort`/`CFRunLoopSource`.
/// - Solo necesita observar eventos, no interceptarlos ni modificarlos (no hace falta un tap que
///   pueda consumir el evento), que es justo lo que permite un monitor global.
///
/// ## Permisos
/// Un monitor global de eventos de teclado (incluye `flagsChanged`) requiere que la app esté
/// habilitada en Ajustes del Sistema → Privacidad y Seguridad → Accesibilidad. Sin ese permiso,
/// `addGlobalMonitorForEvents` no falla ni devuelve `nil`: el token de monitor se crea igual,
/// simplemente no le llegan eventos hasta que se otorgue el permiso. Por eso `start` instala el
/// monitor siempre (así el atajo empieza a andar solo si el permiso se concede después, sin
/// requerir reiniciar la app) y usa `AXIsProcessTrusted()` (sin mostrar el diálogo nativo, para no
/// pedir permiso fuera de este flujo) únicamente para decidir si lanza
/// `GlobalHotkeyServiceError.accessibilityPermissionDenied` y para dejarlo en
/// `lastRegistrationError`. `DictationViewModel` sigue llamando `start` con `try?`, así que el
/// throw no rompe nada más que arranque la app; `currentStatus()` (Fase 6 de MVP3) es la vía por
/// la que la UI se entera de ese estado y lo vuelve a consultar sin reiniciar el servicio.
///
/// ## Limitaciones conocidas
/// - Si el usuario suelta un modificador extra (p. ej. Cmd) mientras Option sigue presionado, esa
///   transición hacia "solo Option" se interpreta como una presión nueva del atajo. Caso borde
///   aceptado para este MVP.
/// - Todavía no hay modo "mantener presionado" (hold-to-talk); ver el TODO en
///   `handleFlagsChanged`.
final class LiveGlobalHotkeyService: GlobalHotkeyServicing {
    /// Modificadores que importan para decidir si "solo Option" está presionado; excluye ruido
    /// como Caps Lock o la tecla Fn.
    private static let relevantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    private var onHotkeyPressed: (@MainActor () -> Void)?
    private var monitor: Any?
    private var lastRelevantFlags: NSEvent.ModifierFlags = []
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
        lastRelevantFlags = []
        lastRegistrationError = nil
        hasStarted = true

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        guard monitor != nil else {
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
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onHotkeyPressed = nil
        lastRelevantFlags = []
        hasStarted = false
    }

    /// Recalculado en cada llamada: no depende de `lastRegistrationError`, que solo refleja lo
    /// que pasó en el último `start`. Así, si el usuario otorga el permiso de Accesibilidad
    /// después de que la app arrancó, la próxima consulta (p. ej. al volver de Ajustes del
    /// Sistema) ve `.active` sin reiniciar el monitor.
    func currentStatus() -> HotkeyStatus {
        guard hasStarted else { return .unknown }
        guard monitor != nil else {
            return .failed(GlobalHotkeyServiceError.registrationFailed.errorDescription ?? GlobalHotkeyServiceError.registrationFailed.localizedDescription)
        }
        return AXIsProcessTrusted() ? .active : .accessibilityPermissionRequired
    }

    /// Dispara el callback solo en la transición hacia "Option solo presionado", nunca mientras
    /// se mantiene presionado: el sistema solo entrega `flagsChanged` cuando el estado de los
    /// modificadores cambia, así que un Option mantenido no genera eventos repetidos y no hace
    /// falta un debounce adicional.
    ///
    /// TODO(post-MVP3): agregar modo "mantener presionado" (hold-to-talk) como alternativa al
    /// toggle actual — probablemente distinguiendo cuánto tiempo pasa entre el `flagsChanged` de
    /// presión y el de liberación de Option.
    private func handleFlagsChanged(_ event: NSEvent) {
        let current = event.modifierFlags.intersection(Self.relevantFlags)
        let wasOptionOnly = lastRelevantFlags == [.option]
        let isOptionOnly = current == [.option]
        lastRelevantFlags = current

        guard isOptionOnly, !wasOptionOnly, let callback = onHotkeyPressed else { return }
        Task { @MainActor in
            callback()
        }
    }
}
