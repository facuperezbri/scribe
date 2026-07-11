import XCTest
@testable import Scribe

/// Cubre que el atajo global ya NO pide activar la ventana principal antes de
/// disparar el flujo centralizado de siempre — el atajo es "background-first" (ver
/// `docs/DECISIONS.md`): grabar/detener no debe traer a Scribe al frente ni robarle el foco a la
/// app en la que está el usuario.
/// Lo mismo aplica al ítem "Iniciar dictado"/"Detener dictado" del menú de la barra de menús
/// (`.menuBar`): el menú ya está visible, así que tampoco activa la ventana. La única vía
/// que sí la activa es `showMainWindow()`, que respalda "Mostrar Scribe" del menú.
/// `WindowActivationServicing` se sigue probando a través de `FakeWindowActivationService` — sin
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

    /// Regla central: presionar el atajo arranca a grabar a través del mismo
    /// `handlePrimaryDictationAction` de siempre, pero sin pedirle nunca a `WindowActivationServicing`
    /// que traiga la ventana al frente.
    func testHotkeyPressDoesNotActivateMainWindowButStillStartsRecording() async {
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

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// El botón de la UI tampoco activa la ventana — ya estaba al frente porque el usuario lo
    /// tocó con el mouse. Ninguno de los dos orígenes de `handlePrimaryDictationAction` debe
    /// activar la ventana automáticamente.
    func testUserInterfaceButtonDoesNotActivateMainWindow() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, windowActivationService: windowActivationService)

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Mientras se transcribe, presiones repetidas del atajo siguen sin activar la ventana ni
    /// arrancar una grabación nueva ni cancelar la transcripción en curso.
    func testHotkeyWhileTranscribingDoesNotActivateWindowOrStartNewRecording() async {
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

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .transcribing)
    }

    /// Con una transcripción previa no vacía, el atajo la reemplaza y arranca a grabar directo
    /// (igual que el botón, sin confirmación bloqueante), y sigue sin activar la ventana.
    func testHotkeyWithNonEmptyTranscriptDoesNotActivateWindowAndStartsRecordingImmediately() async {
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
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Presiones repetidas del atajo mientras se está grabando no activan la ventana ni arrancan
    /// una segunda grabación.
    func testRepeatedHotkeyPressesDoNotActivateWindowOrStartASecondRecording() async {
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
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// "Mostrar Scribe" del menú de la barra de menús es hoy la única acción prevista
    /// que activa la ventana principal — `showMainWindow()` es un simple puente hacia el
    /// servicio inyectado, igual que `registerWindowReopenHandler`.
    func testShowMainWindowActivatesTheWindow() {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, windowActivationService: windowActivationService)

        viewModel.showMainWindow()

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 1)
    }

    /// El origen `.menuBar` es otro punto de entrada al mismo flujo centralizado que
    /// `.userInterface`/`.globalHotkey`, y tampoco activa la ventana por su cuenta: el menú ya
    /// está visible, así que no hace falta traer la ventana principal al frente para grabar.
    func testMenuBarActionDoesNotActivateMainWindowButStillStartsRecording() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let windowActivationService = FakeWindowActivationService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            windowActivationService: windowActivationService,
            audioRecorder: audioRecorder
        )

        viewModel.handlePrimaryDictationAction(source: .menuBar)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(windowActivationService.activateMainWindowCallCount, 0)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// `registerWindowReopenHandler` sigue siendo un simple puente hacia el servicio inyectado:
    /// no decide nada por su cuenta, solo lo reenvía. Sigue vivo para que una acción explícita
    /// futura pueda apoyarse en él sin que `DictationViewModel` conozca `NSWindow`.
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
