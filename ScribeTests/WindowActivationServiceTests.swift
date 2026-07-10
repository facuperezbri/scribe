import XCTest
@testable import Scribe

/// Cubre que el atajo global pide activar la ventana principal antes de disparar el flujo
/// centralizado de siempre (Fase 7 de MVP3), a través de `FakeWindowActivationService` — sin
/// depender de `NSApplication`/`NSWindow` reales, que no se pueden controlar de forma confiable en
/// un test unitario.
@MainActor
final class WindowActivationServiceTests: XCTestCase {
    private func makeViewModel(
        hotkeyService: FakeGlobalHotkeyService,
        windowActivationService: FakeWindowActivationService,
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
            windowActivationService: windowActivationService,
            transcriptionService: transcriptionService
        )
    }

    func testHotkeyPressRequestsWindowActivation() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, windowActivationService: windowActivationService)
        _ = viewModel

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 1)
    }

    /// El botón de la UI no necesita traer la app al frente: ya está al frente porque el usuario
    /// lo tocó con el mouse. Solo el atajo global (que puede venir de cualquier otra app) lo pide.
    func testUserInterfaceButtonDoesNotRequestWindowActivation() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, windowActivationService: windowActivationService)

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// La activación de ventana no reemplaza el flujo centralizado: la primera presión sigue
    /// arrancando la grabación a través del mismo `handlePrimaryDictationAction`.
    func testHotkeyStillUsesCentralizedWorkflowAfterRequestingActivation() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            windowActivationService: windowActivationService,
            audioRecorder: audioRecorder
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 1)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Mientras se transcribe, el atajo sigue pidiendo traer la ventana al frente, pero no arranca
    /// una grabación nueva ni cancela la transcripción en curso.
    func testHotkeyWhileTranscribingRequestsActivationButDoesNotStartNewRecording() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.delayMilliseconds = 200
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            windowActivationService: windowActivationService,
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

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 3)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .transcribing)
    }

    /// Con una transcripción previa no vacía, el atajo pide activar la ventana y dispara la misma
    /// confirmación que el botón, en vez de grabar directamente.
    func testHotkeyWithNonEmptyTranscriptRequestsActivationAndTriggersConfirmation() {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            windowActivationService: windowActivationService,
            audioRecorder: audioRecorder
        )
        viewModel.transcript = "transcripción anterior"

        hotkeyService.simulateHotkeyPressed()

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 1)
        XCTAssertEqual(viewModel.pendingConfirmation, .replaceTranscript)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 0)
    }

    /// Presiones repetidas del atajo mientras hay una confirmación pendiente siguen pidiendo
    /// activar la ventana (es idempotente, sin efecto visible más allá de traerla al frente), pero
    /// no apilan una segunda confirmación ni arrancan una grabación.
    func testRepeatedHotkeyPressesDoNotDuplicateThePendingAction() {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            windowActivationService: windowActivationService,
            audioRecorder: audioRecorder
        )
        viewModel.transcript = "transcripción anterior"

        hotkeyService.simulateHotkeyPressed()
        hotkeyService.simulateHotkeyPressed()
        hotkeyService.simulateHotkeyPressed()

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 3)
        XCTAssertEqual(viewModel.pendingConfirmation, .replaceTranscript)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 0)
    }

    /// `registerWindowReopenHandler` es un simple puente hacia el servicio inyectado: no decide
    /// nada por su cuenta, solo lo reenvía.
    func testRegisterWindowReopenHandlerForwardsToTheInjectedService() {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, windowActivationService: windowActivationService)

        var reopenCallCount = 0
        viewModel.registerWindowReopenHandler { reopenCallCount += 1 }
        windowActivationService.reopenHandler?()

        XCTAssertEqual(reopenCallCount, 1)
    }
}
