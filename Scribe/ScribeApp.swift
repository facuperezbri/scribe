import SwiftUI

@main
struct ScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: appDelegate.dictationViewModel)
                .onAppear {
                    appDelegate.dictationViewModel.registerWindowReopenHandler {
                        openWindow(id: "main")
                    }
                }
        }
        .windowResizability(.contentSize)

        // Fase 4 de MVP4: ítem de la barra de menús para usar Scribe como utilitario en
        // background, sin depender de que la ventana principal esté abierta.
        MenuBarExtra {
            MenuBarContentView(
                viewModel: appDelegate.dictationViewModel,
                onShowMainWindow: appDelegate.dictationViewModel.showMainWindow
            )
        } label: {
            MenuBarStatusIcon(viewModel: appDelegate.dictationViewModel)
        }
    }
}
