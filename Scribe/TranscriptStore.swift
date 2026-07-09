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

    /// `legacyFileURL`, si se provee y el archivo actual todavía no existe, se copia (nunca
    /// se mueve ni se borra) al path actual. Así el archivo `LocalDictate` original queda
    /// intacto y la transcripción actual (`Scribe`) siempre gana si ya existe.
    init(fileURL: URL, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let legacyFileURL {
            Self.migrateLegacyFileIfNeeded(from: legacyFileURL, to: fileURL)
        }
    }

    convenience init() {
        self.init(fileURL: StoragePaths.currentTranscriptFile, legacyFileURL: StoragePaths.legacyTranscriptFile)
        migrateFromUserDefaultsIfNeeded()
    }

    private static func migrateLegacyFileIfNeeded(from legacyURL: URL, to currentURL: URL) {
        guard !FileManager.default.fileExists(atPath: currentURL.path) else { return }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        try? FileManager.default.copyItem(at: legacyURL, to: currentURL)
    }

    /// Migra una transcripción guardada por una versión anterior de la app (que usaba
    /// `UserDefaults`, antes incluso de existir un archivo legacy) al nuevo archivo, una sola vez.
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
