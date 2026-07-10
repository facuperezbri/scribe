import AppKit
import Foundation

/// Contrato mínimo para traer la ventana principal de Scribe al frente (Fase 7 de MVP3). No sabe
/// nada de grabar, transcribir ni de las reglas de negocio de `DictationViewModel`: solo expone
/// "activar la ventana principal", para que el atajo global pueda pedirlo sin que la lógica de
/// grabar/detener viva en dos lugares.
protocol WindowActivationServicing {
    /// Activa la app y trae su ventana principal al frente: la desminimiza si estaba minimizada,
    /// y si no queda ninguna ventana abierta (el usuario la cerró del todo), pide que se vuelva a
    /// abrir a través del handler registrado con `registerReopenHandler`.
    func activateMainWindow()
    /// Conecta la acción `openWindow` de SwiftUI, que `activateMainWindow()` usa como último
    /// recurso cuando no queda ninguna `NSWindow` para traer al frente. Un servicio plano fuera de
    /// la jerarquía de vistas no tiene acceso propio a `@Environment`, así que `ContentView`
    /// registra este puente una sola vez al aparecer.
    func registerReopenHandler(_ handler: @escaping () -> Void)
}

/// Implementación real de `WindowActivationServicing`: usa `NSApplication`/`NSWindow` para traer
/// a Scribe al frente sin importar qué app tenía el foco antes.
final class LiveWindowActivationService: WindowActivationServicing {
    private var reopenHandler: (() -> Void)?

    func activateMainWindow() {
        let app = NSApplication.shared
        if app.isHidden {
            app.unhide(nil)
        }
        app.activate(ignoringOtherApps: true)

        guard let window = app.windows.first else {
            // No queda ninguna ventana (el usuario cerró la última): pedirle a SwiftUI que la
            // vuelva a abrir, si ya se registró el puente. Si todavía no se registró (llamada muy
            // temprana en el arranque), no hay nada más que hacer acá.
            reopenHandler?()
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func registerReopenHandler(_ handler: @escaping () -> Void) {
        reopenHandler = handler
    }
}
