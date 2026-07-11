import AppKit

/// Dueño de `DictationViewModel` a nivel de app, en vez de que `ContentView` lo posea como
/// `@StateObject` (ver `docs/DECISIONS.md`): así el view model sigue existiendo mientras la app
/// esté corriendo, sin importar si la ventana está abierta, minimizada o cerrada.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dictationViewModel = DictationViewModel()
    /// Burbuja flotante de grabación/transcripción. Se crea recién en
    /// `applicationDidFinishLaunching` porque necesita referenciar `dictationViewModel` en su
    /// inicializador, y una propiedad `let` con valor por defecto no puede leer `self` todavía.
    private var recordingOverlayController: RecordingOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordingOverlayController = RecordingOverlayController(viewModel: dictationViewModel)
    }
}
