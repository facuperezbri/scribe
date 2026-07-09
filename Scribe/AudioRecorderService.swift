import AVFoundation

enum AudioRecorderError: LocalizedError {
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "No se pudo iniciar la grabación de audio."
        }
    }
}

protocol AudioRecordingServicing {
    @discardableResult
    func startRecording() throws -> URL
    @discardableResult
    func stopRecording() -> URL?
    func deleteCurrentFile()
    func currentLevel() -> Float
    /// Registra el callback a invocar si la grabación en curso se interrumpe (falla de
    /// codificación, u otra app toma el dispositivo de audio) antes de que el usuario la
    /// detenga por su cuenta. `error` es `nil` cuando AVAudioRecorder reporta la interrupción
    /// sin un `Error` asociado (p. ej. `successfully: false`).
    func setInterruptionHandler(_ handler: @escaping (Error?) -> Void)
}

/// Grava audio del micrófono a un archivo local temporal.
final class AudioRecorderService: NSObject, AudioRecordingServicing, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?
    private var interruptionHandler: ((Error?) -> Void)?

    // TODO(Phase 4): confirmar que 16kHz mono PCM WAV es el formato óptimo de entrada para WhisperKit.
    private var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
    }

    @discardableResult
    func startRecording() throws -> URL {
        deleteCurrentFile()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("localdictate-\(UUID().uuidString).wav")

        let newRecorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
        newRecorder.isMeteringEnabled = true
        newRecorder.delegate = self

        guard newRecorder.record() else {
            throw AudioRecorderError.failedToStart
        }

        recorder = newRecorder
        currentFileURL = fileURL
        return fileURL
    }

    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentFileURL
    }

    /// Borra el archivo de audio temporal actual, si existe.
    func deleteCurrentFile() {
        guard let url = currentFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        currentFileURL = nil
    }

    /// Nivel de entrada actual normalizado a 0...1, para dar una señal visual de que el
    /// micrófono está recibiendo audio. `averagePower` reporta dB (típicamente -160...0);
    /// se usa un piso de ruido simple en vez de una escala perceptual precisa, alcanza para
    /// mostrar actividad.
    func currentLevel() -> Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        guard power.isFinite else { return 0 }
        let noiseFloorDb: Float = -50
        guard power > noiseFloorDb else { return 0 }
        return min(1, (power - noiseFloorDb) / -noiseFloorDb)
    }

    func setInterruptionHandler(_ handler: @escaping (Error?) -> Void) {
        interruptionHandler = handler
    }

    /// `successfully: false` es la señal de AVFoundation de que la grabación terminó por sí
    /// sola sin que `stopRecording()` la haya pedido (p. ej. otra app tomó el dispositivo de
    /// audio). Una detención pedida por el usuario reporta `true` acá y no debe tratarse como
    /// interrupción.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        interruptionHandler?(nil)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        interruptionHandler?(error)
    }
}
