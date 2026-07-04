import AppKit
import Foundation
import WhisperKit

/// Administra la presencia y descarga del modelo de WhisperKit en disco.
///
/// Garantía de red: este tipo nunca inicia una descarga por sí mismo. `isModelInstalled` e
/// `installedModelFolder` solo leen el disco. La única vía de red es `downloadModel`, que
/// se invoca exclusivamente desde una acción explícita del usuario (botón "Descargar modelo").
enum ModelManager {
    // TODO(selección de modelo): "large-v3-v20240930_626MB" es el recomendado por Argmax
    // para mejor precisión multilingüe. Para iterar más rápido en desarrollo, probar "tiny" o "small".
    static let modelVariant = "large-v3-v20240930_626MB"
    static let modelRepo = "argmaxinc/whisperkit-coreml"
    static let modelSizeDescription = "~626 MB"
    static let modelDisplayName = "Whisper large-v3"

    private static let modelFolderDefaultsKey = "LocalDictate.modelFolderPath"

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("LocalDictate/Models", isDirectory: true)
    }

    /// Carpeta local del modelo ya descargado, si todavía existe en disco.
    static var installedModelFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: modelFolderDefaultsKey) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    static var isModelInstalled: Bool {
        installedModelFolder != nil
    }

    @discardableResult
    static func downloadModel(progressCallback: @escaping (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let folder = try await WhisperKit.download(
            variant: modelVariant,
            downloadBase: modelsDirectory,
            from: modelRepo,
            progressCallback: { progress in
                progressCallback(progress.fractionCompleted)
            }
        )

        UserDefaults.standard.set(folder.path, forKey: modelFolderDefaultsKey)
        return folder
    }

    /// Muestra la carpeta del modelo instalado en Finder. No hace nada si aún no existe.
    static func revealInFinder() {
        guard let folder = installedModelFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
