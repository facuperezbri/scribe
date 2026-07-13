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

protocol TranscriptionServicing {
    func transcribe(audioURL: URL) async throws -> String
    func invalidate()
}

/// Envuelve WhisperKit para transcribir audio localmente. Todo el uso de WhisperKit
/// queda aislado dentro de esta clase (y de ModelManager para la gestión del modelo).
final class TranscriptionService: TranscriptionServicing {
    private let modelManager: ModelManaging
    private var whisperKit: WhisperKit?
    private var loadedModelFolder: URL?

    // TODO: permitir inglés o auto-detección desde una pantalla de configuración.
    private let language = "es"

    // Detector de actividad de voz por energía, para descartar grabaciones sin audio real
    // antes de pasarlas por Whisper. Whisper (incluido WhisperKit) alucina frases cortas y
    // muy seguras como "Gracias" ante silencio puro: su `noSpeechThreshold` no filtra ese
    // caso porque el propio `avgLogProb` alto (el modelo está "confiado" de su alucinación)
    // anula el chequeo interno de silencio.
    //
    // El `energyThreshold` default de `EnergyVAD` (0.02) descarta voz real grabada con
    // `AudioRecorderService`: en grabaciones de prueba con micrófono integrado, el ruido de
    // fondo midió ~0.0001–0.004 RMS y la voz normal ~0.005–0.02 RMS, así que 0.02 dejaba
    // casi toda voz por debajo del umbral (transcripción vacía sin error). 0.006 deja margen
    // sobre el ruido medido sin perder voz real.
    private let silenceDetector = EnergyVAD(energyThreshold: 0.006)

    /// Frase de muestra en español con puntuación y mayúsculas correctas, tokenizada y pasada como
    /// "prompt" de Whisper (`DecodingOptions.promptTokens`). Los dictados de esta app son clips
    /// cortos y aislados, sin ningún audio previo real que condicione al modelo: sin este empujón,
    /// Whisper large-v3 tiende a devolver todo en minúscula y sin puntuación en frases cortas,
    /// porque no tiene señal de dónde empieza/termina una oración. El prompt nunca aparece en el
    /// resultado — solo predispone el estilo de lo que sigue, igual que el parámetro `prompt` de
    /// la propia referencia de WhisperKit.
    private static let formattingPromptText = "Hola, ¿cómo estás? Hoy es un buen día para empezar de nuevo."

    init(modelManager: ModelManaging) {
        self.modelManager = modelManager
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let modelFolder = modelManager.installedModelFolder else {
            throw TranscriptionServiceError.modelNotInstalled
        }

        let audioSamples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard !silenceDetector.calculateActiveChunks(in: audioSamples).isEmpty else {
            return ""
        }

        let kit = try await loadedWhisperKit(modelFolder: modelFolder)
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            detectLanguage: false,
            promptTokens: formattingPromptTokens(tokenizer: kit.tokenizer)
        )
        let results: [TranscriptionResult] = try await kit.transcribe(audioArray: audioSamples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formattingPromptTokens(tokenizer: WhisperTokenizer?) -> [Int]? {
        guard let tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + Self.formattingPromptText)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
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
