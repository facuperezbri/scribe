import Foundation

/// Coordina la persistencia de la transcripción en disco: la guarda con un pequeño debounce (para
/// no escribir en cada tecla presionada en el editor) y la carga al arrancar. Separado de
/// `DictationViewModel` porque es coordinación de un `Task` de I/O, sin relación con las reglas de
/// negocio de grabar/transcribir ni con el búfer de deshacer (`previousTranscript`), que sigue
/// viviendo en el view model por estar ligado a `@Published`.
@MainActor
final class TranscriptSessionController {
    private static let saveDebounce: Duration = .milliseconds(500)

    private let transcriptStore: TranscriptStoring
    private var pendingSaveTask: Task<Void, Never>?

    init(transcriptStore: TranscriptStoring) {
        self.transcriptStore = transcriptStore
    }

    func loadSavedTranscript() -> String? {
        transcriptStore.loadTranscript()
    }

    func scheduleSave(_ text: String) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            self?.transcriptStore.saveTranscript(text)
        }
    }
}
