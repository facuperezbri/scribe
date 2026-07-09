import Foundation

/// Rutas de almacenamiento local bajo Application Support.
///
/// `currentFolderName` es el branding actual (Scribe); `legacyFolderName` es el branding
/// anterior (LocalDictate). El Bundle Identifier sigue siendo `com.localdictate.app` a
/// propósito (ver README), pero los datos en disco migran a la carpeta actual.
enum StoragePaths {
    static let currentFolderName = "Scribe"
    static let legacyFolderName = "LocalDictate"

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var currentAppDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(currentFolderName, isDirectory: true)
    }

    static var legacyAppDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(legacyFolderName, isDirectory: true)
    }

    static var currentTranscriptFile: URL {
        currentAppDirectory.appendingPathComponent("last-transcript.txt")
    }

    static var legacyTranscriptFile: URL {
        legacyAppDirectory.appendingPathComponent("last-transcript.txt")
    }

    static var currentModelsDirectory: URL {
        currentAppDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var legacyModelsDirectory: URL {
        legacyAppDirectory.appendingPathComponent("Models", isDirectory: true)
    }
}
