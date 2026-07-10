import XCTest
@testable import Scribe

/// Cubre `overlayPhase`/`lastTranscriptionOutcome` (Fase 5 de MVP4): la señal que consume la
/// burbuja flotante para saber cuándo mostrarse (grabando/transcribiendo), cuándo mostrar "Listo"
/// brevemente (solo tras un éxito) y cuándo ocultarse sin más (fracaso, cancelación, o cualquier
/// reposo que no sea "recién terminó bien" — por ejemplo, al abrir la app con una transcripción
/// restaurada del disco).
@MainActor
final class DictationViewModelOverlayPhaseTests: XCTestCase {
    private func makeViewModel(
        audioRecorder: FakeAudioRecordingService = FakeAudioRecordingService(),
        transcriptionService: FakeTranscriptionService = FakeTranscriptionService()
    ) -> DictationViewModel {
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = true
        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = .authorized

        return DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            transcriptionService: transcriptionService
        )
    }

    func testIdleAtLaunchIsHiddenEvenWithARestoredTranscript() {
        let viewModel = makeViewModel()
        viewModel.transcript = "transcripción restaurada del disco"

        XCTAssertEqual(viewModel.overlayPhase, .hidden)
    }

    func testRecordingShowsTheOverlay() async {
        let viewModel = makeViewModel()

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.session, .recording)
        XCTAssertEqual(viewModel.overlayPhase, .recording)
    }

    func testTranscribingShowsTheOverlay() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.delayMilliseconds = 200
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.session, .transcribing)
        XCTAssertEqual(viewModel.overlayPhase, .transcribing)
    }

    func testSuccessfulTranscriptionFlashesDone() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola mundo")
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.lastTranscriptionOutcome, .success)
        XCTAssertEqual(viewModel.overlayPhase, .done)
    }

    func testFailedTranscriptionHidesWithoutFlashingDone() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .failure(NSError(domain: "test", code: 1))
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertNotNil(viewModel.state.error)
        XCTAssertEqual(viewModel.lastTranscriptionOutcome, .failure)
        XCTAssertEqual(viewModel.overlayPhase, .hidden)
    }

    func testCancellingTranscriptionHidesWithoutFlashingDone() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.delayMilliseconds = 200
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.overlayPhase, .transcribing)

        viewModel.cancelTranscription()

        XCTAssertEqual(viewModel.lastTranscriptionOutcome, .cancelled)
        XCTAssertEqual(viewModel.overlayPhase, .hidden)
    }

    func testStartingANewRecordingImmediatelyClearsAPreviousDoneFlash() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola mundo")
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.overlayPhase, .done)

        viewModel.handlePrimaryDictationAction()

        XCTAssertNil(viewModel.lastTranscriptionOutcome)
        XCTAssertNotEqual(viewModel.overlayPhase, .done)
    }
}
