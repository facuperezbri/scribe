import XCTest
@testable import Scribe

/// Cubre los flujos completos de la Fase 7: acciones bloqueadas mientras el view model está
/// ocupado, las dos confirmaciones destructivas (reemplazar o limpiar una transcripción no
/// vacía) y el mapeo de errores de transcripción a `AppError`. Los estados iniciales
/// (modelo instalado+permiso autorizado / modelo faltante / micrófono denegado) y la
/// restauración de la última transcripción ya están cubiertos en
/// `DictationViewModelDependencyInjectionTests`; no se duplican aquí.
@MainActor
final class DictationViewModelWorkflowTests: XCTestCase {
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
            transcriptionService: transcriptionService
        )
    }

    func testStartWhileTranscribingIsBlocked() async {
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.delayMilliseconds = 200
        let viewModel = makeViewModel(audioRecorder: audioRecorder, transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .transcribing)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .transcribing)
    }

    func testNewRecordingWithNonEmptyTranscriptStartsImmediatelyWithoutConfirmation() async {
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)
        viewModel.transcript = "transcripción anterior"

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
        XCTAssertEqual(viewModel.transcript, "transcripción anterior")
    }

    func testReplacingATranscriptSavesThePreviousOneForUndo() async {
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("transcripción nueva")
        let viewModel = makeViewModel(audioRecorder: audioRecorder, transcriptionService: transcriptionService)
        viewModel.transcript = "transcripción anterior"

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(viewModel.previousTranscript, "todavía no se perdió nada mientras se graba")

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.transcript, "transcripción nueva")
        XCTAssertEqual(viewModel.previousTranscript, "transcripción anterior")
    }

    func testRestorePreviousTranscriptSwapsBackAndClearsTheBuffer() async {
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("transcripción nueva")
        let viewModel = makeViewModel(audioRecorder: audioRecorder, transcriptionService: transcriptionService)
        viewModel.transcript = "transcripción anterior"

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        viewModel.restorePreviousTranscript()

        XCTAssertEqual(viewModel.transcript, "transcripción anterior")
        XCTAssertNil(viewModel.previousTranscript)
    }

    func testRestorePreviousTranscriptDoesNothingWithoutABuffer() {
        let viewModel = makeViewModel()
        viewModel.transcript = "algo"

        viewModel.restorePreviousTranscript()

        XCTAssertEqual(viewModel.transcript, "algo")
        XCTAssertNil(viewModel.previousTranscript)
    }

    func testClearingATranscriptAlsoClearsTheUndoBuffer() async {
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("transcripción nueva")
        let viewModel = makeViewModel(audioRecorder: audioRecorder, transcriptionService: transcriptionService)
        viewModel.transcript = "transcripción anterior"

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.previousTranscript, "transcripción anterior")

        viewModel.clearTranscript()
        viewModel.confirmPendingAction()

        XCTAssertEqual(viewModel.transcript, "")
        XCTAssertNil(viewModel.previousTranscript)
    }

    func testClearingNonEmptyTranscriptRequiresConfirmation() {
        let viewModel = makeViewModel()
        viewModel.transcript = "transcripción anterior"

        viewModel.clearTranscript()

        XCTAssertEqual(viewModel.pendingConfirmation, .clearTranscript)
        XCTAssertEqual(viewModel.transcript, "transcripción anterior")

        viewModel.confirmPendingAction()

        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertEqual(viewModel.transcript, "")
    }

    func testClearingEmptyTranscriptNeedsNoConfirmation() {
        let viewModel = makeViewModel()

        viewModel.clearTranscript()

        XCTAssertNil(viewModel.pendingConfirmation)
    }

    func testClearTranscriptReturnsCorrectStateWhenModelMissing() {
        let viewModel = makeViewModel(modelInstalled: false)
        viewModel.transcript = "transcripción anterior"

        viewModel.clearTranscript()
        viewModel.confirmPendingAction()

        XCTAssertEqual(viewModel.transcript, "")
        XCTAssertEqual(viewModel.state.model, .missing)
        XCTAssertEqual(viewModel.state.session, .idle)
    }

    func testTranscriptionErrorMapsToTypedError() async {
        struct SomeTranscriptionFailure: Error {}
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .failure(SomeTranscriptionFailure())
        let viewModel = makeViewModel(transcriptionService: transcriptionService)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.state.error?.category, .transcription)
    }
}
