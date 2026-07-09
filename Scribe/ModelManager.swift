import AppKit
import Foundation
import WhisperKit

protocol ModelManaging {
    var installedModelFolder: URL? { get }
    var isModelInstalled: Bool { get }
    func downloadModel(progressCallback: @escaping (Double) -> Void) async throws -> URL
    func revealInFinder()
}

/// Administra la presencia y descarga del modelo de WhisperKit en disco.
///
/// Garantía de red: este tipo nunca inicia una descarga por sí mismo. `isModelInstalled` e
/// `installedModelFolder` solo leen el disco. La única vía de red es `downloadModel`, que
/// se invoca exclusivamente desde una acción explícita del usuario (botón "Descargar modelo").
final class ModelManager: ModelManaging {
    // TODO(selección de modelo): "large-v3-v20240930_626MB" es el recomendado por Argmax
    // para mejor precisión multilingüe. Para iterar más rápido en desarrollo, probar "tiny" o "small".
    static let modelVariant = "large-v3-v20240930_626MB"
    static let modelRepo = "argmaxinc/whisperkit-coreml"
    static let modelSizeDescription = "~626 MB"
    static let modelDisplayName = "Whisper large-v3"

    private static let modelFolderDefaultsKey = "Scribe.modelFolderPath"
    private static let legacyModelFolderDefaultsKey = "LocalDictate.modelFolderPath"

    private let userDefaults: UserDefaults
    private let modelsDirectory: URL

    /// El modelo (~626 MB) nunca se copia entre carpetas: copiarlo o moverlo sería un riesgo
    /// innecesario para un archivo tan grande. En cambio, esta clase sigue leyendo desde donde
    /// sea que esté instalado (potencialmente bajo `LocalDictate/Models`, si se descargó con una
    /// versión anterior) y solo las descargas nuevas van a `modelsDirectory` (por defecto,
    /// `Scribe/Models`). La única migración es la de la entry de `UserDefaults` que guarda esa
    /// ruta, para que quede con el branding actual sin tocar el archivo en disco.
    init(userDefaults: UserDefaults = .standard, modelsDirectory: URL = StoragePaths.currentModelsDirectory) {
        self.userDefaults = userDefaults
        self.modelsDirectory = modelsDirectory
        Self.migrateModelFolderDefaultsKeyIfNeeded(userDefaults: userDefaults)
    }

    private static func migrateModelFolderDefaultsKeyIfNeeded(userDefaults: UserDefaults) {
        guard userDefaults.string(forKey: modelFolderDefaultsKey) == nil else { return }
        guard let legacyPath = userDefaults.string(forKey: legacyModelFolderDefaultsKey) else { return }
        userDefaults.set(legacyPath, forKey: modelFolderDefaultsKey)
    }

    /// Carpeta local del modelo ya descargado, si todavía existe en disco. Puede estar bajo la
    /// carpeta legacy (`LocalDictate/Models`) o la actual (`Scribe/Models`); no importa, porque
    /// la ruta completa quedó guardada en `UserDefaults` al momento de la descarga.
    var installedModelFolder: URL? {
        guard let path = userDefaults.string(forKey: Self.modelFolderDefaultsKey) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    var isModelInstalled: Bool {
        installedModelFolder != nil
    }

    @discardableResult
    func downloadModel(progressCallback: @escaping (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let folder = try await WhisperKit.download(
            variant: Self.modelVariant,
            downloadBase: modelsDirectory,
            from: Self.modelRepo,
            progressCallback: { progress in
                progressCallback(progress.fractionCompleted)
            }
        )

        userDefaults.set(folder.path, forKey: Self.modelFolderDefaultsKey)
        return folder
    }

    /// Muestra la carpeta del modelo instalado en Finder. No hace nada si aún no existe.
    func revealInFinder() {
        guard let folder = installedModelFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
