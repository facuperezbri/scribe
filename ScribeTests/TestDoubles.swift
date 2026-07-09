import Foundation
@testable import Scribe

/// Fakes livianos de los servicios inyectables, para usar en tests sin tocar
/// micrófono real, WhisperKit, descargas de red ni el portapapeles del sistema.

final class FakeAudioRecordingService: AudioRecordingServicing {
    var startRecordingResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/fake-recording.wav"))
    var stopRecordingResult: URL? = URL(fileURLWithPath: "/tmp/fake-recording.wav")
    var level: Float = 0
    private(set) var startRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    private(set) var deleteCurrentFileCallCount = 0
    private var interruptionHandler: ((Error?) -> Void)?

    func startRecording() throws -> URL {
        startRecordingCallCount += 1
        return try startRecordingResult.get()
    }

    func stopRecording() -> URL? {
        stopRecordingCallCount += 1
        return stopRecordingResult
    }

    func deleteCurrentFile() {
        deleteCurrentFileCallCount += 1
    }

    func currentLevel() -> Float {
        level
    }

    func setInterruptionHandler(_ handler: @escaping (Error?) -> Void) {
        interruptionHandler = handler
    }

    /// Simula que `AVAudioRecorderDelegate` reportó una interrupción, sin depender de
    /// hardware de audio real.
    func simulateInterruption(error: Error? = nil) {
        interruptionHandler?(error)
    }
}

final class FakeTranscriptionService: TranscriptionServicing {
    var transcribeResult: Result<String, Error> = .success("")
    /// Simula una transcripción lenta, para tests que necesitan cancelar o arrancar una
    /// grabación nueva mientras la anterior sigue "en vuelo".
    var delayMilliseconds: UInt64 = 0
    private(set) var invalidateCallCount = 0

    func transcribe(audioURL: URL) async throws -> String {
        if delayMilliseconds > 0 {
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        return try transcribeResult.get()
    }

    func invalidate() {
        invalidateCallCount += 1
    }
}

final class FakeModelManager: ModelManaging {
    var isModelInstalled = false
    var installedModelFolder: URL?
    var downloadResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/fake-model"))
    private(set) var revealInFinderCallCount = 0

    func downloadModel(progressCallback: @escaping (Double) -> Void) async throws -> URL {
        progressCallback(1.0)
        return try downloadResult.get()
    }

    func revealInFinder() {
        revealInFinderCallCount += 1
    }
}

final class FakeMicrophonePermissionManager: MicrophonePermissionManaging {
    var status: MicrophonePermissionStatus = .authorized
    var requestAccessResult = true

    func currentStatus() -> MicrophonePermissionStatus {
        status
    }

    func requestAccess() async -> Bool {
        requestAccessResult
    }
}

final class FakeClipboardService: ClipboardServicing {
    private(set) var copiedText: String?

    func copy(_ text: String) {
        copiedText = text
    }
}

final class FakeTranscriptStore: TranscriptStoring {
    var storedTranscript: String?

    func loadTranscript() -> String? {
        storedTranscript
    }

    func saveTranscript(_ text: String) {
        storedTranscript = text
    }
}
