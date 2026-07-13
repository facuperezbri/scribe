import XCTest
@testable import Scribe

/// Cubre `primaryState`/`primaryStateTitle`/`primaryStateHint`/`showCopyCallToAction`,
/// el mapeo de estado a copy del área central de la ventana compacta.
///
/// Usa `FakeGlobalHotkeyService` (en vez del `DictationViewModel()` real que usan otros archivos
/// de test) porque estos casos dependen de `hotkeyStatus`, y el servicio real consulta
/// `AXIsProcessTrusted()` de verdad: sin un `Fake` fijo, el resultado dependería del permiso de
/// Accesibilidad de la máquina/build que corre los tests (distinto en un build sin firma real, como
/// el que usa CI) en vez de ser determinístico.
@MainActor
final class DictationViewModelPrimaryStateTests: XCTestCase {
    private func makeViewModel() -> DictationViewModel {
        DictationViewModel(globalHotkeyService: FakeGlobalHotkeyService())
    }

    func testReadyState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        viewModel.transcript = ""

        XCTAssertEqual(viewModel.primaryState, .ready)
        XCTAssertEqual(viewModel.primaryStateTitle, "Listo para dictar")
        XCTAssertEqual(viewModel.primaryStateHint, "Mantené Fn presionado para dictar")
        XCTAssertFalse(viewModel.showCopyCallToAction)
    }

    func testRecordingState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .recording, error: nil)

        XCTAssertEqual(viewModel.primaryState, .recording)
        XCTAssertEqual(viewModel.primaryStateTitle, "Grabando...")
        XCTAssertNil(viewModel.primaryStateHint)
        XCTAssertFalse(viewModel.showCopyCallToAction)
    }

    func testStoppingState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .stoppingRecording, error: nil)

        XCTAssertEqual(viewModel.primaryState, .stoppingRecording)
        XCTAssertEqual(viewModel.primaryStateTitle, "Deteniendo...")
    }

    func testTranscribingState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .transcribing, error: nil)

        XCTAssertEqual(viewModel.primaryState, .transcribing)
        XCTAssertEqual(viewModel.primaryStateTitle, "Transcribiendo localmente...")
    }

    func testTranscriptReadyState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        viewModel.transcript = "hola mundo"

        XCTAssertEqual(viewModel.primaryState, .transcriptReady)
        XCTAssertEqual(viewModel.primaryStateTitle, "Transcripción lista")
        XCTAssertNil(viewModel.primaryStateHint)
        XCTAssertTrue(viewModel.showCopyCallToAction)
    }

    func testMicrophoneDeniedState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .denied, model: .installed, session: .idle, error: nil)

        XCTAssertEqual(viewModel.primaryState, .microphoneDenied)
        XCTAssertEqual(viewModel.primaryStateTitle, "Permiso de micrófono requerido")
    }

    func testMissingModelState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .missing, session: .idle, error: nil)

        XCTAssertEqual(viewModel.primaryState, .missingModel)
        XCTAssertEqual(viewModel.primaryStateTitle, "Modelo requerido")
    }

    func testDownloadingModelState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .downloading(progress: 0.4), session: .idle, error: nil)

        XCTAssertEqual(viewModel.primaryState, .downloadingModel)
        XCTAssertEqual(viewModel.primaryStateTitle, "Descargando modelo...")
    }

    func testInputMonitoringRequiredState() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        viewModel.transcript = ""
        viewModel.hotkeyStatus = .inputMonitoringPermissionRequired

        XCTAssertEqual(viewModel.primaryState, .inputMonitoringRequired)
        XCTAssertEqual(viewModel.primaryStateTitle, "Permiso de Monitoreo de entrada requerido")
    }

    func testErrorStateTakesPriorityOverEverythingElse() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(
            permission: .denied,
            model: .missing,
            session: .idle,
            error: AppError(category: .unknown, message: "boom")
        )

        XCTAssertEqual(viewModel.primaryState, .error("boom"))
        XCTAssertEqual(viewModel.primaryStateTitle, "boom")
    }

    func testActiveSessionOutranksModelAndPermissionBlockers() {
        let viewModel = makeViewModel()
        viewModel.state = AppState(permission: .denied, model: .missing, session: .recording, error: nil)

        XCTAssertEqual(viewModel.primaryState, .recording)
        XCTAssertEqual(viewModel.primaryStateTitle, "Grabando...")
    }
}
