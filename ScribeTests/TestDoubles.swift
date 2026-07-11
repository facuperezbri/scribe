import AppKit
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

final class FakeGlobalHotkeyService: GlobalHotkeyServicing {
    var startResult: Result<Void, Error> = .success(())
    /// Lo que devuelve `currentStatus()`. Los tests lo cambian entre llamadas para simular, por
    /// ejemplo, que el usuario otorgó el permiso de Accesibilidad después de que la app arrancó.
    var statusResult: HotkeyStatus = .active
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var currentStatusCallCount = 0
    private var onHotkeyPressed: (@MainActor () -> Void)?

    func start(onHotkeyPressed: @escaping @MainActor () -> Void) throws {
        startCallCount += 1
        self.onHotkeyPressed = onHotkeyPressed
        try startResult.get()
    }

    func stop() {
        stopCallCount += 1
        onHotkeyPressed = nil
    }

    func currentStatus() -> HotkeyStatus {
        currentStatusCallCount += 1
        return statusResult
    }

    /// Simula que el atajo global se detectó, sin depender de un event tap real.
    @MainActor
    func simulateHotkeyPressed() {
        onHotkeyPressed?()
    }
}

final class FakeWindowActivationService: WindowActivationServicing {
    private(set) var activateMainWindowCallCount = 0
    private(set) var reopenHandler: (() -> Void)?

    func activateMainWindow() {
        activateMainWindowCallCount += 1
    }

    func registerReopenHandler(_ handler: @escaping () -> Void) {
        reopenHandler = handler
    }
}

final class FakeAutoPasteService: AutoPasteServicing {
    var targetToCapture: AutoPasteTarget?
    var pasteResult: AutoPasteResult = .pasted
    private(set) var captureTargetCallCount = 0
    private(set) var pasteCallCount = 0
    private(set) var lastPastedText: String?
    private(set) var lastPasteTarget: AutoPasteTarget?

    func captureTarget() -> AutoPasteTarget? {
        captureTargetCallCount += 1
        return targetToCapture
    }

    func paste(text: String, target: AutoPasteTarget) async -> AutoPasteResult {
        pasteCallCount += 1
        lastPastedText = text
        lastPasteTarget = target
        return pasteResult
    }
}

/// `AutoPasteTarget` envuelve un `NSRunningApplication` vivo, que no tiene inicializador público:
/// los tests usan `.current` (el propio proceso de test) como relleno, ya que solo los campos
/// planos (`bundleIdentifier`/`localizedName`/`processIdentifier`) importan para las aserciones.
extension AutoPasteTarget {
    static func fake(
        processIdentifier: pid_t = 12345,
        bundleIdentifier: String? = "com.example.target",
        localizedName: String? = "Target de prueba"
    ) -> AutoPasteTarget {
        AutoPasteTarget(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            runningApplication: .current
        )
    }
}
