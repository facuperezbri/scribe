import XCTest
@testable import Scribe

/// Cubre `performAutoPasteIfNeeded(text:)`, el efecto secundario que dispara
/// `AutoPasteServicing.paste(text:target:)` tras una transcripción exitosa. La captura del destino
/// (Fase 3) y el `LiveAutoPasteService.paste` en sí (Fase 4, `AutoPasteServiceTests`) ya están
/// cubiertos aparte; esto prueba solo el cableado: cuándo `DictationViewModel` decide llamar a
/// `paste` y cuándo no.
@MainActor
final class DictationViewModelAutoPasteTriggerTests: XCTestCase {
    private func makeViewModel(
        autoPasteService: FakeAutoPasteService,
        transcriptionService: FakeTranscriptionService = FakeTranscriptionService(),
        hotkeyService: FakeGlobalHotkeyService = FakeGlobalHotkeyService(),
        audioRecorder: FakeAudioRecordingService = FakeAudioRecordingService()
    ) -> DictationViewModel {
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = true

        return DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: modelManager,
            microphonePermissionManager: FakeMicrophonePermissionManager(),
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            globalHotkeyService: hotkeyService,
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled })
        )
    }

    /// Camino feliz: hay destino capturado y la transcripción da texto no vacío, así que se pega.
    func testSuccessfulTranscriptionWithCapturedTargetTriggersPaste() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.target")
        autoPasteService.pasteResult = .pasted
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola mundo")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.pasteCallCount, 1)
        XCTAssertEqual(autoPasteService.lastPastedText, "hola mundo")
        XCTAssertEqual(autoPasteService.lastPasteTarget?.bundleIdentifier, "com.example.target")
        XCTAssertEqual(viewModel.lastAutoPasteResult, .pasted)
        XCTAssertNil(viewModel.capturedAutoPasteTarget)
    }

    /// Sin destino capturado (p. ej. el dictado arrancó desde la propia ventana de Scribe) no hay
    /// nada a qué pegarle.
    func testNoCapturedTargetDoesNotTriggerPaste() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = nil
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.pasteCallCount, 0)
        XCTAssertNil(viewModel.lastAutoPasteResult)
    }

    /// Transcripción vacía: no hay texto útil para pegar, aunque haya destino capturado.
    func testEmptyTranscriptDoesNotTriggerPaste() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.pasteCallCount, 0)
        XCTAssertNil(viewModel.lastAutoPasteResult)
    }

    /// Transcripción fallida: el texto nunca se produjo, así que no hay nada que pegar.
    func testFailedTranscriptionDoesNotTriggerPaste() async {
        struct SomeTranscriptionFailure: Error {}
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .failure(SomeTranscriptionFailure())
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.lastTranscriptionOutcome, .failure)
        XCTAssertEqual(autoPasteService.pasteCallCount, 0)
        XCTAssertNil(viewModel.lastAutoPasteResult)
    }

    /// Transcripción cancelada (una grabación nueva arranca mientras la anterior seguía "en
    /// vuelo"): el resultado tardío no debe disparar un paste para un intento que el usuario ya
    /// descartó.
    func testCancelledTranscriptionDoesNotTriggerPaste() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola")
        transcriptionService.delayMilliseconds = 200
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .transcribing)

        viewModel.cancelTranscription()
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(viewModel.lastTranscriptionOutcome, .cancelled)
        XCTAssertEqual(autoPasteService.pasteCallCount, 0)
        XCTAssertNil(viewModel.lastAutoPasteResult)
    }

    /// Fase 7: si el auto-paste de una sesión sigue "en vuelo" (p. ej. la reactivación de
    /// `LiveAutoPasteService` tarda) y el usuario ya arrancó a dictar de nuevo antes de que
    /// resuelva, ese resultado tardío no debe pisar `lastAutoPasteResult` de la sesión nueva.
    func testALateAutoPasteResultFromASupersededSessionDoesNotOverwriteTheNewSession() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.first")
        autoPasteService.pasteResult = .pasted
        autoPasteService.delayMilliseconds = 200
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("primera frase")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        // Primera sesión: grabar, transcribir y disparar un auto-paste lento (200ms) que todavía
        // no resolvió cuando arranca la segunda sesión.
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(autoPasteService.pasteCallCount, 1)
        XCTAssertNil(viewModel.lastAutoPasteResult, "el paste lento todavía no resolvió")

        // Segunda sesión: arranca y termina (sin destino capturado esta vez) antes de que el
        // auto-paste de la primera sesión resuelva.
        autoPasteService.targetToCapture = nil
        autoPasteService.delayMilliseconds = 0
        transcriptionService.transcribeResult = .success("segunda frase")
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(viewModel.lastAutoPasteResult, "la segunda sesión no capturó destino, así que no hay nada que pegar")

        // El paste lento de la primera sesión termina recién ahora; su resultado tardío se
        // descarta en vez de pisar el estado (ya `nil`) de la segunda sesión.
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(viewModel.lastAutoPasteResult)
    }
}
