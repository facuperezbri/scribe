import Foundation

/// Resultado de un intento de transcripción. `.cancelled` cubre tanto una cancelación explícita
/// como un resultado que llegó tarde (tras arrancar un intento nuevo): en ambos casos, quien llamó
/// ya dejó de estar interesado en este resultado puntual.
enum TranscriptionAttemptOutcome: Equatable {
    case success(String)
    case failure(AppError)
    case cancelled
}

/// Ejecuta un intento de transcripción y descarta un resultado que llega tarde, sin importar por
/// qué (cancelación explícita, o un intento nuevo que ya arrancó antes de que este termine).
/// Separado de `DictationViewModel` porque comparar contra un id de intento es la única lógica no
/// trivial de `transcribe(url:)`; el resto es puro manejo de `@Published` que debe seguir viviendo
/// en el view model.
@MainActor
final class TranscriptionAttemptCoordinator {
    private let transcriptionService: TranscriptionServicing
    private var currentAttempt: UUID?

    init(transcriptionService: TranscriptionServicing) {
        self.transcriptionService = transcriptionService
    }

    /// Marca el intento en curso como no relevante, sin cancelar la tarea que lo está esperando
    /// (eso sigue a cargo de quien posea ese `Task`): el próximo resultado que llegue para este
    /// intento se descarta en `transcribe(url:)`.
    func cancel() {
        currentAttempt = nil
    }

    func transcribe(url: URL) async -> TranscriptionAttemptOutcome {
        let attemptID = UUID()
        currentAttempt = attemptID
        do {
            let text = try await transcriptionService.transcribe(audioURL: url)
            guard currentAttempt == attemptID else { return .cancelled }
            currentAttempt = nil
            return .success(text)
        } catch {
            guard currentAttempt == attemptID else { return .cancelled }
            currentAttempt = nil
            return .failure(AppError(category: .transcription, underlying: error))
        }
    }
}
