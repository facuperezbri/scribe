import Foundation

/// Sondea tiempo transcurrido y nivel de entrada mientras se graba, en su propio `Task` (Fase 8
/// del rediseño estilo Wispr, extraído de `DictationViewModel`). Vive fuera del view model para
/// que este no tenga que administrar el `Task` de polling además del resto del flujo de
/// grabar/detener/transcribir.
@MainActor
final class RecordingMeter {
    private static let pollInterval: Duration = .milliseconds(200)

    private let audioRecorder: AudioRecordingServicing
    private var task: Task<Void, Never>?

    init(audioRecorder: AudioRecordingServicing) {
        self.audioRecorder = audioRecorder
    }

    func start(onTick: @escaping (_ elapsed: TimeInterval, _ level: Float) -> Void) {
        let start = Date()
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                onTick(Date().timeIntervalSince(start), self?.audioRecorder.currentLevel() ?? 0)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
