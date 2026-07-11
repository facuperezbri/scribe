import XCTest
@testable import Scribe

/// Cubre que `DictationViewModel` captura el destino de auto-paste en el momento correcto
/// (sincrónico, antes de arrancar a grabar) para los tres orígenes de
/// `handlePrimaryDictationAction`, y que la ausencia de destino nunca bloquea el dictado — el
/// pegado en sí todavía no existe (llega en la Fase 4); esto solo prueba la captura.
@MainActor
final class DictationViewModelAutoPasteCaptureTests: XCTestCase {
    private func makeViewModel(
        autoPasteService: FakeAutoPasteService,
        hotkeyService: FakeGlobalHotkeyService = FakeGlobalHotkeyService(),
        audioRecorder: FakeAudioRecordingService = FakeAudioRecordingService()
    ) -> DictationViewModel {
        DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: FakeModelManager(),
            microphonePermissionManager: FakeMicrophonePermissionManager(),
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            globalHotkeyService: hotkeyService,
            autoPasteService: autoPasteService,
            transcriptionService: FakeTranscriptionService()
        )
    }

    /// El atajo global es el caso principal que auto-paste necesita: Scribe nunca estuvo al
    /// frente, así que la app capturada es la que el usuario tenía enfocada.
    func testGlobalHotkeyCapturesTheConfiguredTargetBeforeRecording() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.notes")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(autoPasteService: autoPasteService, hotkeyService: hotkeyService)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.captureTargetCallCount, 1)
        XCTAssertEqual(viewModel.capturedAutoPasteTarget?.bundleIdentifier, "com.example.notes")
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// El botón de la ventana principal también captura a través del mismo punto de entrada — es
    /// `LiveAutoPasteService.captureTarget()` quien decide devolver `nil` cuando la app frontmost
    /// es la propia Scribe, no una regla especial acá.
    func testUserInterfaceButtonAlsoCapturesThroughTheSameEntryPoint() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.editor")
        let viewModel = makeViewModel(autoPasteService: autoPasteService)

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.captureTargetCallCount, 1)
        XCTAssertEqual(viewModel.capturedAutoPasteTarget?.bundleIdentifier, "com.example.editor")
    }

    /// El ítem de la barra de menús es el tercer origen: misma captura, mismo punto de entrada.
    func testMenuBarActionCapturesTheConfiguredTarget() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.browser")
        let viewModel = makeViewModel(autoPasteService: autoPasteService)

        viewModel.handlePrimaryDictationAction(source: .menuBar)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.captureTargetCallCount, 1)
        XCTAssertEqual(viewModel.capturedAutoPasteTarget?.bundleIdentifier, "com.example.browser")
    }

    /// Cuando `captureTarget()` no devuelve nada (p. ej. Scribe era la app frontmost), el dictado
    /// arranca igual: la ausencia de destino es no-fatal, solo implica que no habrá auto-paste
    /// más adelante.
    func testMissingTargetIsNonFatalAndRecordingStillStarts() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = nil
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.captureTargetCallCount, 1)
        XCTAssertNil(viewModel.capturedAutoPasteTarget)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Cada nueva grabación vuelve a capturar y pisa el destino anterior — no queda un destino
    /// viejo colgado de una grabación previa.
    func testANewRecordingRecapturesAndOverwritesThePreviousTarget() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.first")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(autoPasteService: autoPasteService, hotkeyService: hotkeyService)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.capturedAutoPasteTarget?.bundleIdentifier, "com.example.first")

        // Detiene la primera grabación y espera a que la transcripción (instantánea, sin delay
        // configurado) termine y vuelva a `.idle` antes de arrancar la segunda.
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .idle)

        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.second")
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.captureTargetCallCount, 2)
        XCTAssertEqual(viewModel.capturedAutoPasteTarget?.bundleIdentifier, "com.example.second")
    }
}
