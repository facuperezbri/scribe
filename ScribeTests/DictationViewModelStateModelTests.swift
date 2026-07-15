import XCTest
@testable import Scribe

/// Cubre las garantías del modelo de estado dimensional: un único punto de entrada
/// (`handlePrimaryDictationAction`) que sirve tanto para la UI como para el atajo global,
/// seguro ante toques repetidos, y que limpia `state.error` cuando
/// un reintento tiene éxito.
@MainActor
final class DictationViewModelStateModelTests: XCTestCase {
    private func makeViewModel(
        audioRecorder: FakeAudioRecordingService = FakeAudioRecordingService(),
        transcriptionService: FakeTranscriptionService = FakeTranscriptionService(),
        modelInstalled: Bool = true,
        permissionStatus: MicrophonePermissionStatus = .authorized
    ) -> DictationViewModel {
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = modelInstalled
        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = permissionStatus

        return DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            transcriptionService: transcriptionService,
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )
    }

    func testRapidRepeatedStartDoesNotStartTwoRecordings() async {
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction()
        viewModel.handlePrimaryDictationAction()
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    func testGlobalHotkeySourceStartsRecordingLikeUserInterface() async {
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction(source: .globalHotkey)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    func testStoppingRecordingTranscribesWhenModelInstalled() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola")
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertNil(viewModel.state.error)
        XCTAssertEqual(viewModel.transcript, "hola")
    }

    func testErrorClearsAfterSuccessfulRetry() async {
        let audioRecorder = FakeAudioRecordingService()
        audioRecorder.startRecordingResult = .failure(AudioRecorderError.failedToStart)
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(viewModel.state.error)

        audioRecorder.startRecordingResult = .success(URL(fileURLWithPath: "/tmp/fake-recording.wav"))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.state.error)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    func testLateTranscriptionResultAfterCancelDoesNotOverwriteNewRecording() async {
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("resultado viejo")
        transcriptionService.delayMilliseconds = 300
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .transcribing)

        viewModel.cancelTranscription()
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(viewModel.state.session, .recording)
        XCTAssertEqual(viewModel.transcript, "")
    }
}
