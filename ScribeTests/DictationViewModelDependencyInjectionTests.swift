import XCTest
@testable import Scribe

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
            transcriptionService: FakeTranscriptionService(),
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )

        return (viewModel, modelManager, permissionManager, clipboardService, transcriptStore)
    }

    func testReadyStateWhenModelInstalledAndPermissionAuthorized() {
        let (viewModel, _, _, _, _) = makeViewModel(modelInstalled: true, permissionStatus: .authorized)
        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.state.model, .installed)
        XCTAssertNil(viewModel.state.error)
    }

    func testMissingModelStateWhenModelNotInstalled() {
        let (viewModel, _, _, _, _) = makeViewModel(modelInstalled: false, permissionStatus: .authorized)
        XCTAssertEqual(viewModel.state.model, .missing)
    }

    func testMicrophoneDeniedStateWhenPermissionDenied() {
        let (viewModel, _, _, _, _) = makeViewModel(modelInstalled: true, permissionStatus: .denied)
        XCTAssertEqual(viewModel.state.permission, .denied)
        XCTAssertTrue(viewModel.isError)
    }

    func testCopyTranscriptUsesInjectedClipboardService() {
        let (viewModel, _, _, clipboardService, _) = makeViewModel()
        viewModel.transcript = "hola mundo"

        viewModel.copyTranscript()

        XCTAssertEqual(clipboardService.copiedText, "hola mundo")
    }

    /// `autoPasteService` no se llama todavía desde ningún flujo (eso llega en una fase
    /// posterior): esta prueba solo confirma que la inyección compila y no rompe el arranque.
    func testViewModelCanBeConstructedWithAFakeAutoPasteService() {
        let autoPasteService = FakeAutoPasteService()

        let viewModel = DictationViewModel(
            audioRecorder: FakeAudioRecordingService(),
            modelManager: FakeModelManager(),
            microphonePermissionManager: FakeMicrophonePermissionManager(),
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            autoPasteService: autoPasteService,
            transcriptionService: FakeTranscriptionService(),
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(autoPasteService.captureTargetCallCount, 0)
        XCTAssertEqual(autoPasteService.pasteCallCount, 0)
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
            transcriptionService: FakeTranscriptionService(),
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )

        XCTAssertEqual(viewModel.transcript, "transcripción previa")
    }
}
