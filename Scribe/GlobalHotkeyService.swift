import Foundation

/// Error de registro de un atajo de teclado global.
enum GlobalHotkeyServiceError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "No se pudo registrar el atajo de teclado global."
        }
    }
}

/// Contrato mínimo para un servicio de atajo de teclado global: solo notifica que el atajo se
/// presionó, sin conocer qué debe pasar después. `DictationViewModel.handlePrimaryDictationAction`
/// sigue siendo el único lugar que decide qué hacer (grabar o detener), así que esta capa no
/// puede convertirse en un segundo flujo de negocio.
protocol GlobalHotkeyServicing {
    /// Arranca el servicio. `onHotkeyPressed` se invoca en el actor principal cada vez que se
    /// detecta el atajo. Puede lanzar si el registro a nivel de sistema falla.
    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws
    /// Detiene el servicio y libera cualquier registro a nivel de sistema.
    func stop()
}

/// Implementación real de `GlobalHotkeyServicing`.
///
/// Fase 4 de MVP3: todavía no registra nada a nivel de sistema, solo guarda el callback para que
/// el resto de la app (composición en `DictationViewModel`) ya quede conectada.
/// Fase 5 de MVP3 debe reemplazar `start(onHotkeyPressed:)` para instalar el atajo real
/// (Control+Option+Space, vía `NSEvent.addGlobalMonitorForEvents` o un event tap de Carbon) y
/// llamar a `onHotkeyPressed` cuando se detecte, y `stop()` para removerlo.
final class LiveGlobalHotkeyService: GlobalHotkeyServicing {
    private var onHotkeyPressed: (@MainActor () -> Void)?

    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws {
        // TODO(Fase 5 de MVP3): registrar Control+Option+Space a nivel de sistema acá.
        self.onHotkeyPressed = onHotkeyPressed
    }

    func stop() {
        onHotkeyPressed = nil
    }
}
