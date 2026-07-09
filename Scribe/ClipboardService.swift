import AppKit

/// Copia texto al portapapeles de macOS.
protocol ClipboardServicing {
    func copy(_ text: String)
}

final class ClipboardService: ClipboardServicing {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
