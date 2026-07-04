import XCTest
@testable import LocalDictate

/// Confirma que `DictationViewModel` puede construirse enteramente con fakes: sin
/// micrófono real, sin WhisperKit, sin descargas de modelo y sin portapapeles real.
@MainActor
final class DictationViewModelDependencyInjectionTests: XCTestCase {
    private func makeViewModel(
        modelInstalled: Bool = true,
        permissionStatus: MicrophonePermissionStatus = .authorized
    ) -> (DictationViewModel, FakeModelManager, FakeMicrophonePermissionManager, FakeClipboardService, FakeTranscriptStore) {
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = modelInstalled

        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = permissionStatus

        let clipboardService = FakeClipboardService()
        let transcriptStore = FakeTranscriptStore()

        let viewModel = DictationViewModel(
            audioRecorder: FakeAudioRecordingService(),
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: clipboardService,
            transcriptStore: transcriptStore,
            transcriptionService: FakeTranscriptionService()
        )

        return (viewModel, modelManager, permissionManager, clipboardService, transcriptStore)
    }

    func testReadyStateWhenModelInstalledAndPermissionAuthorized() {
        let (viewModel, _, _, _, _) = makeViewModel(modelInstalled: true, permissionStatus: .authorized)
        XCTAssertEqual(viewModel.state, .ready)
    }

    func testMissingModelStateWhenModelNotInstalled() {
        let (viewModel, _, _, _, _) = makeViewModel(modelInstalled: false, permissionStatus: .authorized)
        XCTAssertEqual(viewModel.state, .missingModel)
    }

    func testMicrophoneDeniedStateWhenPermissionDenied() {
        let (viewModel, _, _, _, _) = makeViewModel(modelInstalled: true, permissionStatus: .denied)
        XCTAssertEqual(viewModel.state, .microphonePermissionDenied)
    }

    func testCopyTranscriptUsesInjectedClipboardService() {
        let (viewModel, _, _, clipboardService, _) = makeViewModel()
        viewModel.transcript = "hola mundo"

        viewModel.copyTranscript()

        XCTAssertEqual(clipboardService.copiedText, "hola mundo")
    }

    func testTranscriptRestoredFromInjectedTranscriptStore() {
        let transcriptStore = FakeTranscriptStore()
        transcriptStore.storedTranscript = "transcripción previa"

        let viewModel = DictationViewModel(
            audioRecorder: FakeAudioRecordingService(),
            modelManager: FakeModelManager(),
            microphonePermissionManager: FakeMicrophonePermissionManager(),
            clipboardService: FakeClipboardService(),
            transcriptStore: transcriptStore,
            transcriptionService: FakeTranscriptionService()
        )

        XCTAssertEqual(viewModel.transcript, "transcripción previa")
    }
}
