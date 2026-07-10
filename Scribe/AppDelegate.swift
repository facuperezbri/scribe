import AppKit

/// Dueño de `DictationViewModel` a nivel de app (Fase 7 de MVP3), en vez de que `ContentView` lo
/// posea como `@StateObject`. Antes, cerrar la ventana principal destruía la instancia de
/// `ContentView` y con ella el view model: el monitor global del atajo (Fn + Espacio, que vive
/// adentro vía `GlobalHotkeyServicing`) capturaba `self` como `weak`, así que el atajo dejaba de andar en
/// cuanto se cerraba la ventana. Con el view model viviendo acá, sigue existiendo mientras la app
/// esté corriendo, sin importar si la ventana está abierta, minimizada o cerrada.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dictationViewModel = DictationViewModel()
}
