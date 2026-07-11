import XCTest
@testable import Scribe

/// Cubre la preferencia mínima de Fase 6 (`isAutoPasteEnabled`/`setAutoPasteEnabled`), su
/// persistencia invertida en `UserDefaults` (mismo patrón que `showOnboardingWelcome`, ver
/// `DictationViewModelOnboardingTests`), el gating que agrega en `performAutoPasteIfNeeded`, y el
/// mapeo de `autoPasteStatusText` para el texto de feedback del menú de la barra de menús.
@MainActor
final class DictationViewModelAutoPasteToggleTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DictationViewModelAutoPasteToggleTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    private func makeViewModel(
        autoPasteService: AutoPasteServicing = FakeAutoPasteService(),
        transcriptionService: TranscriptionServicing = FakeTranscriptionService(),
        hotkeyService: FakeGlobalHotkeyService = FakeGlobalHotkeyService()
    ) -> DictationViewModel {
        DictationViewModel(
            modelManager: {
                let modelManager = FakeModelManager()
                modelManager.isModelInstalled = true
                return modelManager
            }(),
            globalHotkeyService: hotkeyService,
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            userDefaults: userDefaults
        )
    }

    // MARK: - isAutoPasteEnabled / setAutoPasteEnabled

    func testAutoPasteIsEnabledByDefaultWhenNeverToggledBefore() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.isAutoPasteEnabled)
    }

    func testAutoPasteIsDisabledWhenPreviouslyDisabled() {
        userDefaults.set(true, forKey: "Scribe.hasDisabledAutoPaste")

        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.isAutoPasteEnabled)
    }

    func testDisablingAutoPastePersistsTheInvertedKey() {
        let viewModel = makeViewModel()

        viewModel.setAutoPasteEnabled(false)

        XCTAssertFalse(viewModel.isAutoPasteEnabled)
        XCTAssertTrue(userDefaults.bool(forKey: "Scribe.hasDisabledAutoPaste"))
    }

    func testReenablingAutoPasteAfterDisablingItClearsTheInvertedKey() {
        let viewModel = makeViewModel()
        viewModel.setAutoPasteEnabled(false)

        viewModel.setAutoPasteEnabled(true)

        XCTAssertTrue(viewModel.isAutoPasteEnabled)
        XCTAssertFalse(userDefaults.bool(forKey: "Scribe.hasDisabledAutoPaste"))
    }

    // MARK: - performAutoPasteIfNeeded gating

    /// Con el toggle apagado no se llama a `paste`, aunque haya destino capturado y texto no
    /// vacío — el destino capturado igual se limpia, para no dejarlo colgado para el próximo intento.
    func testDisabledAutoPasteSkipsPasteEvenWithACapturedTargetAndText() async {
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.targetToCapture = .fake(bundleIdentifier: "com.example.target")
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.transcribeResult = .success("hola mundo")
        let hotkeyService = FakeGlobalHotkeyService()
        let viewModel = makeViewModel(
            autoPasteService: autoPasteService,
            transcriptionService: transcriptionService,
            hotkeyService: hotkeyService
        )
        viewModel.setAutoPasteEnabled(false)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(autoPasteService.pasteCallCount, 0)
        XCTAssertNil(viewModel.lastAutoPasteResult)
        XCTAssertNil(viewModel.capturedAutoPasteTarget)
    }

    // MARK: - autoPasteStatusText

    func testAutoPasteStatusTextIsNilWhenThereIsNoResultYet() {
        let viewModel = makeViewModel()

        XCTAssertNil(viewModel.autoPasteStatusText)
    }

    func testAutoPasteStatusTextIsNilForSilentOutcomes() async {
        let silentOutcomes: [AutoPasteResult] = [.pasted, .noTarget, .emptyText]

        for outcome in silentOutcomes {
            let autoPasteService = FakeAutoPasteService()
            autoPasteService.targetToCapture = .fake()
            autoPasteService.pasteResult = outcome
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

            XCTAssertNil(viewModel.autoPasteStatusText, "outcome \(outcome) should not surface status text")
        }
    }

    func testAutoPasteStatusTextDescribesEachFailureOutcome() async {
        let expectedMessages: [AutoPasteResult: String] = [
            .targetUnavailable: "Auto-paste: la app destino ya no está disponible.",
            .accessibilityPermissionMissing: "Auto-paste: falta el permiso de Accesibilidad.",
            .secureField: "Auto-paste: no se pegó en un campo que parece contraseña.",
            .pasteboardFailed: "Auto-paste: no se pudo pegar. Usá \"Copiar última transcripción\".",
            .eventPostFailed: "Auto-paste: no se pudo pegar. Usá \"Copiar última transcripción\".",
            .unknown: "Auto-paste: no se pudo pegar. Usá \"Copiar última transcripción\"."
        ]

        for (outcome, expectedMessage) in expectedMessages {
            let autoPasteService = FakeAutoPasteService()
            autoPasteService.targetToCapture = .fake()
            autoPasteService.pasteResult = outcome
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

            XCTAssertEqual(viewModel.autoPasteStatusText, expectedMessage, "unexpected message for outcome \(outcome)")
        }
    }
}
