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
    }
}
