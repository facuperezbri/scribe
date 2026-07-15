import XCTest
@testable import Scribe

final class AppErrorTests: XCTestCase {
    func testCategoryIsPreservedRegardlessOfUnderlyingError() {
        struct SomeUnderlyingError: Error {}

        let appError = AppError(category: .transcription, underlying: SomeUnderlyingError())

        XCTAssertEqual(appError.category, .transcription)
    }

    func testDefaultMessageIsUsedWhenNoneProvided() {
        let appError = AppError(category: .clipboard)

        XCTAssertEqual(appError.message, AppErrorCategory.clipboard.defaultMessage)
    }

    func testExplicitMessageOverridesTheCategoryDefault() {
        let appError = AppError(category: .recording, message: "mensaje específico")

        XCTAssertEqual(appError.category, .recording)
        XCTAssertEqual(appError.message, "mensaje específico")
    }
}

/// Confirma que los estados de error del view model se pueden inspeccionar por categoría,
/// sin comparar el texto (en español) que ve el usuario.
@MainActor
final class DictationViewModelErrorCategoryTests: XCTestCase {
    func testBeginRecordingFailureIsCategorizedAsRecording() async {
        let audioRecorder = FakeAudioRecordingService()
        audioRecorder.startRecordingResult = .failure(AudioRecorderError.failedToStart)

        let viewModel = DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: FakeModelManager(),
            microphonePermissionManager: FakeMicrophonePermissionManager(),
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            transcriptionService: FakeTranscriptionService(),
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        guard let appError = viewModel.state.error else {
            return XCTFail("Se esperaba un AppError en state.error")
        }
        XCTAssertEqual(appError.category, .recording)
    }

    func testRestrictedMicrophoneIsCategorizedAsMicrophonePermission() {
        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = .restricted
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = true

        let viewModel = DictationViewModel(
            audioRecorder: FakeAudioRecordingService(),
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            transcriptionService: FakeTranscriptionService(),
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )

        guard let appError = viewModel.state.error else {
            return XCTFail("Se esperaba un AppError en state.error")
        }
        XCTAssertEqual(appError.category, .microphonePermission)
    }
}
