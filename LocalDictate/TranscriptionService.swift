import Foundation
import WhisperKit

enum TranscriptionServiceError: LocalizedError {
    case modelNotInstalled

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "El modelo de transcripción no está instalado."
        }
    }
}

/// Envuelve WhisperKit para transcribir audio localmente. Todo el uso de WhisperKit
/// queda aislado dentro de esta clase (y de ModelManager para la gestión del modelo).
final class TranscriptionService {
    private var whisperKit: WhisperKit?
    private var loadedModelFolder: URL?

    // TODO(Fase 5+): permitir inglés o auto-detección desde una pantalla de configuración.
    private let language = "es"

    func transcribe(audioURL: URL) async throws -> String {
        guard let modelFolder = ModelManager.installedModelFolder else {
            throw TranscriptionServiceError.modelNotInstalled
        }

        let kit = try await loadedWhisperKit(modelFolder: modelFolder)
        let options = DecodingOptions(task: .transcribe, language: language, detectLanguage: false)
        let result: TranscriptionResult? = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return result?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func loadedWhisperKit(modelFolder: URL) async throws -> WhisperKit {
        if let whisperKit, loadedModelFolder == modelFolder {
            return whisperKit
        }
        let config = WhisperKitConfig(modelFolder: modelFolder.path, download: false)
        let kit = try await WhisperKit(config)
        whisperKit = kit
        loadedModelFolder = modelFolder
        return kit
    }

    /// Descarta el WhisperKit cargado en memoria para forzar una recarga desde disco.
    /// Debe llamarse tras cualquier (re)descarga del modelo, ya que una descarga puede
    /// reemplazar los archivos del modelo en la misma carpeta sin cambiar su ruta.
    func invalidate() {
        whisperKit = nil
        loadedModelFolder = nil
    }
}
