import XCTest
@testable import Scribe

/// Cubre el reformateo on-device (Fase de reformateo): que se aplique cuando está habilitado y
/// Apple Intelligence disponible, que el toggle lo desactive, que el perfil elegido se le pase al
/// servicio, y que una falla o indisponibilidad caigan de forma silenciosa al texto literal — sin
/// bloquear ni degradar el resto del flujo de dictado.
@MainActor
final class DictationViewModelFormattingTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DictationViewModelFormattingTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    private func makeViewModel(
        transcriptFormattingService: FakeTranscriptFormattingService = FakeTranscriptFormattingService(),
        transcriptionService: FakeTranscriptionService = FakeTranscriptionService(),
        appleIntelligenceAvailable: Bool = true,
        hotkeyService: FakeGlobalHotkeyService = FakeGlobalHotkeyService()
    ) -> DictationViewModel {
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = true
        let appleIntelligenceController = AppleIntelligenceAvailabilityController(
            unavailableReasonProvider: { appleIntelligenceAvailable ? nil : .appleIntelligenceNotEnabled }
        )

        return DictationViewModel(
            modelManager: modelManager,
            globalHotkeyService: hotkeyService,
            transcriptionService: transcriptionService,
            transcriptFormattingService: transcriptFormattingService,
            appleIntelligenceAvailabilityController: appleIntelligenceController,
            userDefaults: userDefaults
        )
    }

    /// Dicta (vía el atajo global) y detiene, esperando a que la transcripción + reformateo
    /// terminen antes de aserciones.
    private func dictateAndWait(_ hotkeyService: FakeGlobalHotkeyService) async {
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
    }

    func testFormattingIsAppliedWhenEnabledAndAvailable() async {
        let formattingService = FakeTranscriptFormattingService()
        formattingService.reformatResult = .success("texto limpio")
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("o sea texto con muletismos")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            transcriptFormattingService: formattingService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(formattingService.reformatCallCount, 1)
        XCTAssertEqual(formattingService.lastReformattedText, "o sea texto con muletismos")
        XCTAssertEqual(viewModel.transcript, "texto limpio")
    }

    func testFormattingUsesTheSelectedProfile() async {
        let formattingService = FakeTranscriptFormattingService()
        formattingService.reformatResult = .success("texto formal")
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            transcriptFormattingService: formattingService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )
        viewModel.setFormattingProfile(.formal)

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(formattingService.lastProfile, .formal)
    }

    func testDisablingFormattingSkipsReformatAndKeepsLiteralText() async {
        let formattingService = FakeTranscriptFormattingService()
        formattingService.reformatResult = .success("texto limpio")
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("texto literal")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            transcriptFormattingService: formattingService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )
        viewModel.setFormattingEnabled(false)

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(formattingService.reformatCallCount, 0)
        XCTAssertEqual(viewModel.transcript, "texto literal")
    }

    func testUnavailableAppleIntelligenceSkipsReformatAndKeepsLiteralText() async {
        let formattingService = FakeTranscriptFormattingService()
        formattingService.reformatResult = .success("texto limpio")
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("texto literal")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            transcriptFormattingService: formattingService,
            transcriptionService: transcriptionService,
            appleIntelligenceAvailable: false,
            hotkeyService: hotkeyService
        )

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(formattingService.reformatCallCount, 0)
        XCTAssertEqual(viewModel.transcript, "texto literal")
    }

    func testReformatFailureFallsBackToLiteralTextWithoutBlockingTheFlow() async {
        struct SomeReformatFailure: Error {}
        let formattingService = FakeTranscriptFormattingService()
        formattingService.reformatResult = .failure(SomeReformatFailure())
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("texto literal")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            transcriptFormattingService: formattingService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(formattingService.reformatCallCount, 1)
        XCTAssertEqual(viewModel.transcript, "texto literal")
        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertNil(viewModel.state.error)
    }

    func testEmptyTranscriptSkipsReformatEntirely() async {
        let formattingService = FakeTranscriptFormattingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("")
        let hotkeyService = FakeGlobalHotkeyService()
        _ = makeViewModel(
            transcriptFormattingService: formattingService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(formattingService.reformatCallCount, 0)
    }

    func testReformattedTextIsWhatGetsAutoPasted() async {
        let formattingService = FakeTranscriptFormattingService()
        formattingService.reformatResult = .success("texto limpio")
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("o sea texto")
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake()
        let hotkeyService = FakeGlobalHotkeyService()
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = true
        let appleIntelligenceController = AppleIntelligenceAvailabilityController(unavailableReasonProvider: { nil })

        let viewModel = DictationViewModel(
            modelManager: modelManager,
            globalHotkeyService: hotkeyService,
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            transcriptFormattingService: formattingService,
            appleIntelligenceAvailabilityController: appleIntelligenceController,
            userDefaults: userDefaults
        )

        await dictateAndWait(hotkeyService)

        XCTAssertEqual(autoPasteService.lastPastedText, "texto limpio")
        _ = viewModel
    }
}
