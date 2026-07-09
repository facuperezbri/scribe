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

    // MARK: - Fase 6: estado del atajo y permiso de Accesibilidad

    func testHotkeyStatusReflectsActiveAfterInit() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = .active
        let viewModel = makeViewModel(hotkeyService: hotkeyService)

        XCTAssertEqual(viewModel.hotkeyStatus, .active)
    }

    /// El registro sigue instalando el monitor (Fase 5) y solo el `AXIsProcessTrusted` falla;
    /// eso no debe impedir que la app arranque ni tumbar `init`.
    func testHotkeyStatusReflectsAccessibilityPermissionRequiredAfterInit() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.accessibilityPermissionDenied)
        hotkeyService.statusResult = .accessibilityPermissionRequired
        let viewModel = makeViewModel(hotkeyService: hotkeyService)

        XCTAssertEqual(viewModel.hotkeyStatus, .accessibilityPermissionRequired)
    }

    /// Una falla de registro no relacionada con Accesibilidad tampoco es fatal: el botón de la UI
    /// sigue grabando con normalidad.
    func testNonFatalRegistrationFailureDoesNotPreventNormalUse() async {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.registrationFailed)
        hotkeyService.statusResult = .failed("No se pudo registrar el atajo de teclado global.")
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        XCTAssertEqual(viewModel.hotkeyStatus, .failed("No se pudo registrar el atajo de teclado global."))

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Simula que el usuario otorgó el permiso de Accesibilidad después de que la app arrancó:
    /// `refreshHotkeyStatus()` debe reflejarlo sin reiniciar el servicio.
    func testRefreshHotkeyStatusUpdatesAfterPermissionGrantedLater() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.accessibilityPermissionDenied)
        hotkeyService.statusResult = .accessibilityPermissionRequired
        let viewModel = makeViewModel(hotkeyService: hotkeyService)
        XCTAssertEqual(viewModel.hotkeyStatus, .accessibilityPermissionRequired)

        hotkeyService.statusResult = .active
        viewModel.refreshHotkeyStatus()

        XCTAssertEqual(viewModel.hotkeyStatus, .active)
    }

    /// El fake sigue disparando el flujo centralizado sin importar el estado reportado por
    /// `currentStatus()` — esa distinción es solo para la UI, no cambia el cableado del atajo.
    func testGlobalHotkeyStillUsesCentralizedWorkflowWhenAccessibilityPermissionIsRequired() async {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = .accessibilityPermissionRequired
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// `LiveGlobalHotkeyService.currentStatus()` antes de `start` no depende de Accesibilidad:
    /// no hay callback ni monitor instalado todavía, así que siempre es `.unknown`.
    func testLiveServiceStatusIsUnknownBeforeStart() {
        let service = LiveGlobalHotkeyService()
        XCTAssertEqual(service.currentStatus(), .unknown)
    }

    /// Después de `start`, el estado real depende del permiso de Accesibilidad de esta máquina
    /// (no controlable en CI), así que solo se verifica que deje de ser `.unknown`/`.failed` —
    /// sin asumir si el proceso está o no confiado.
    func testLiveServiceStatusIsActiveOrPermissionRequiredAfterStart() {
        let service = LiveGlobalHotkeyService()
        try? service.start {}

        switch service.currentStatus() {
        case .active, .accessibilityPermissionRequired:
            break
        case .unknown, .failed:
            XCTFail("Se esperaba .active o .accessibilityPermissionRequired después de start, se obtuvo \(service.currentStatus())")
        }
    }

    /// `stop()` vuelve a dejar el estado en `.unknown`, igual que antes de llamar a `start`.
    func testLiveServiceStatusReturnsToUnknownAfterStop() {
        let service = LiveGlobalHotkeyService()
        try? service.start {}

        service.stop()

        XCTAssertEqual(service.currentStatus(), .unknown)
    }
}
