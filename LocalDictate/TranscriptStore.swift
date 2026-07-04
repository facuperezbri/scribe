import Foundation

protocol TranscriptStoring {
    func loadTranscript() -> String?
    func saveTranscript(_ text: String)
}

/// Persiste la última transcripción en `UserDefaults`.
///
/// TODO(Fase 4): mover a un archivo bajo Application Support — `UserDefaults` no es
/// apropiado para texto potencialmente largo.
final class UserDefaultsTranscriptStore: TranscriptStoring {
    private static let key = "LocalDictate.lastTranscript"

    func loadTranscript() -> String? {
        UserDefaults.standard.string(forKey: Self.key)
    }

    func saveTranscript(_ text: String) {
        if text.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set(text, forKey: Self.key)
        }
    }
}
