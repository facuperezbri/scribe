import XCTest
@testable import Scribe

/// Cubre el contrato de `GlobalHotkeyServicing` a través del fake (sin depender de un evento de
/// teclado real) y que `DictationViewModel` conecta el callback del atajo global con
/// `handlePrimaryDictationAction(source: .globalHotkey)` sin duplicar el flujo de grabar/detener.
@MainActor
final class GlobalHotkeyServiceTests: XCTestCase {
    func testStartRegistersCallbackThatCanBeSimulated() throws {
        let service = FakeGlobalHotkeyService()
        var pressed = false

        try service.start { pressed = true }

        XCTAssertEqual(service.startCallCount, 1)
        service.simulateHotkeyPressed()
        XCTAssertTrue(pressed)
    }

    func testStartPropagatesRegistrationFailure() {
        let service = FakeGlobalHotkeyService()
        service.startResult = .failure(GlobalHotkeyServiceError.registrationFailed)

        XCTAssertThrowsError(try service.start {})
    }

    func testStopClearsCallback() throws {
        let service = FakeGlobalHotkeyService()
        var pressed = false
        try service.start { pressed = true }

        service.stop()
        service.simulateHotkeyPressed()

        XCTAssertFalse(pressed)
        XCTAssertEqual(service.stopCallCount, 1)
    }

    func testGlobalHotkeyPressStartsRecordingLikeTheUserInterfaceButton() async {
        let audioRecorder = FakeAudioRecordingService()
        let hotkeyService = FakeGlobalHotkeyService()
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = true
        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = .authorized

        let viewModel = DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            globalHotkeyService: hotkeyService,
            transcriptionService: FakeTranscriptionService()
        )

        XCTAssertEqual(hotkeyService.startCallCount, 1)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }
}
