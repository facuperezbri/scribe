import XCTest
@testable import Scribe

/// Cubre el contrato de `GlobalHotkeyServicing` a través del fake (sin depender de un evento de
/// teclado real) y que `DictationViewModel` conecta el callback del atajo global con
/// `handlePrimaryDictationAction(source: .globalHotkey)` sin duplicar el flujo de grabar/detener.
///
/// Los casos que ejercitan `DictationViewModel` completo (Fase 5 de MVP3: atajo de Option en modo
/// toggle) simulan la presión del atajo a través de `FakeGlobalHotkeyService.simulateHotkeyPressed()`,
/// nunca con un evento real de teclado — eso es justamente lo que `LiveGlobalHotkeyService`
/// traduce a esa llamada, y queda fuera del alcance de un test unitario.
@MainActor
final class GlobalHotkeyServiceTests: XCTestCase {
    private func makeViewModel(
        hotkeyService: FakeGlobalHotkeyService,
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
            globalHotkeyService: hotkeyService,
            transcriptionService: transcriptionService
        )
    }

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
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        XCTAssertEqual(hotkeyService.startCallCount, 1)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Toggle: la segunda presión de Option, con la grabación en curso, detiene y arranca la
    /// transcripción — el mismo flujo que produce un segundo toque del botón de la UI.
    func testSecondGlobalHotkeyPressStopsRecordingAndTranscribes() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .recording)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.stopRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .idle)
    }

    /// Regla de comportamiento 3: mientras se transcribe, el atajo no debe arrancar una
    /// grabación nueva — igual que el botón, queda bloqueado por `isBusy`.
    func testGlobalHotkeyPressWhileTranscribingDoesNotStartNewRecording() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.delayMilliseconds = 200
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder,
            transcriptionService: transcriptionService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .transcribing)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .transcribing)
    }

    /// Regla de comportamiento 4: con una transcripción no vacía, el atajo no la sobreescribe
    /// directamente, dispara la misma confirmación que usa el botón.
    func testGlobalHotkeyPressWithNonEmptyTranscriptRequiresConfirmation() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)
        viewModel.transcript = "transcripción anterior"

        hotkeyService.simulateHotkeyPressed()

        XCTAssertEqual(viewModel.pendingConfirmation, .replaceTranscript)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 0)

        viewModel.confirmPendingAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Regla de comportamiento 5: con una confirmación ya pendiente, una presión adicional del
    /// atajo no debe apilar una segunda confirmación ni saltearla.
    func testGlobalHotkeyPressWithPendingConfirmationDoesNotDuplicateIt() {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)
        viewModel.transcript = "transcripción anterior"

        hotkeyService.simulateHotkeyPressed()
        XCTAssertEqual(viewModel.pendingConfirmation, .replaceTranscript)

        hotkeyService.simulateHotkeyPressed()

        XCTAssertEqual(viewModel.pendingConfirmation, .replaceTranscript)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 0)
    }

    /// Regla de comportamiento 6: sin permiso de micrófono, el atajo no arranca a grabar; el
    /// estado de permiso sigue siendo la única autoridad, igual que con el botón.
    func testGlobalHotkeyPressWithDeniedMicrophonePermissionDoesNotStartRecording() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder,
            permissionStatus: .denied
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 0)
        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.state.permission, .denied)
    }

    /// Regla de comportamiento 7: con el modelo faltante, el atajo preserva el comportamiento
    /// existente. Arrancar a grabar no depende del modelo (solo detener y transcribir sí), así
    /// que la segunda presión debe volver a `.idle` sin transcribir ni descargar nada sola.
    func testGlobalHotkeyPressWithMissingModelPreservesExistingBehavior() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder,
            modelInstalled: false
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .recording)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.model, .missing)
        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.transcript, "")
    }

    /// El botón de la UI sigue funcionando igual con el servicio de atajo inyectado — el atajo
    /// es un origen más de `handlePrimaryDictationAction`, no un flujo paralelo.
    func testUserInterfaceButtonStillWorksWithHotkeyServiceInjected() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }
}
