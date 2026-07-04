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
}

/// Grava audio del micrófono a un archivo local temporal.
final class AudioRecorderService: NSObject, AudioRecordingServicing {
    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?

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
}
