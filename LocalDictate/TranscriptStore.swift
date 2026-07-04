import Foundation

protocol TranscriptStoring {
    func loadTranscript() -> String?
    func saveTranscript(_ text: String)
}

/// Persiste la última transcripción en un archivo local bajo Application Support.
/// `UserDefaults` no es apropiado para texto potencialmente largo.
final class FileTranscriptStore: TranscriptStoring {
    private static let legacyUserDefaultsKey = "LocalDictate.lastTranscript"

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("LocalDictate", isDirectory: true)
        self.init(fileURL: directory.appendingPathComponent("last-transcript.txt"))
        migrateFromUserDefaultsIfNeeded()
    }

    /// Migra una transcripción guardada por una versión anterior de la app (que usaba
    /// `UserDefaults`) al nuevo archivo, una sola vez.
    private func migrateFromUserDefaultsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let legacy = UserDefaults.standard.string(forKey: Self.legacyUserDefaultsKey), !legacy.isEmpty else { return }
        try? legacy.write(to: fileURL, atomically: true, encoding: .utf8)
        UserDefaults.standard.removeObject(forKey: Self.legacyUserDefaultsKey)
    }

    func loadTranscript() -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func saveTranscript(_ text: String) {
        if text.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
