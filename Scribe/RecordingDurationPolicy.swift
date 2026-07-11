import Foundation

/// Nivel de aviso por duración de grabación. Depende solo de cuánto tiempo pasó: quien llama
/// decide si corresponde mostrarlo (p. ej., solo mientras `state.session == .recording`).
enum RecordingDurationWarning: Equatable {
    case none
    case soft
    case strong
}

/// Umbrales de duración de grabación, separados de `DictationViewModel` para poder testearlos
/// sin instanciar el resto del flujo de grabar/transcribir.
enum RecordingDurationPolicy {
    static let softThreshold: TimeInterval = 120
    static let strongThreshold: TimeInterval = 300

    static func warning(forElapsed elapsed: TimeInterval) -> RecordingDurationWarning {
        if elapsed >= strongThreshold { return .strong }
        if elapsed >= softThreshold { return .soft }
        return .none
    }
}
