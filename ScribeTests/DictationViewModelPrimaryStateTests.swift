import XCTest
@testable import Scribe

/// Cubre `primaryState`/`primaryStateTitle`/`primaryStateHint`/`showCopyCallToAction`,
/// el mapeo de estado a copy del área central de la ventana compacta.
@MainActor
final class DictationViewModelPrimaryStateTests: XCTestCase {
    func testReadyState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        viewModel.transcript = ""

        XCTAssertEqual(viewModel.primaryState, .ready)
        XCTAssertEqual(viewModel.primaryStateTitle, "Listo para dictar")
        XCTAssertEqual(viewModel.primaryStateHint, "Presioná Fn + Espacio para dictar")
        XCTAssertFalse(viewModel.showCopyCallToAction)
    }

    func testRecordingState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .recording, error: nil)

        XCTAssertEqual(viewModel.primaryState, .recording)
        XCTAssertEqual(viewModel.primaryStateTitle, "Grabando...")
        XCTAssertNil(viewModel.primaryStateHint)
        XCTAssertFalse(viewModel.showCopyCallToAction)
    }

    func testStoppingState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .stoppingRecording, error: nil)

        XCTAssertEqual(viewModel.primaryState, .stoppingRecording)
        XCTAssertEqual(viewModel.primaryStateTitle, "Deteniendo...")
    }

    func testTranscribingState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .transcribing, error: nil)

        XCTAssertEqual(viewModel.primaryState, .transcribing)
        XCTAssertEqual(viewModel.primaryStateTitle, "Transcribiendo localmente...")
    }

    func testTranscriptReadyState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        viewModel.transcript = "hola mundo"

        XCTAssertEqual(viewModel.primaryState, .transcriptReady)
        XCTAssertEqual(viewModel.primaryStateTitle, "Transcripción lista")
        XCTAssertNil(viewModel.primaryStateHint)
        XCTAssertTrue(viewModel.showCopyCallToAction)
    }

    func testMicrophoneDeniedState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .denied, model: .installed, session: .idle, error: nil)

        XCTAssertEqual(viewModel.primaryState, .microphoneDenied)
        XCTAssertEqual(viewModel.primaryStateTitle, "Permiso de micrófono requerido")
    }

    func testMissingModelState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .missing, session: .idle, error: nil)

        XCTAssertEqual(viewModel.primaryState, .missingModel)
        XCTAssertEqual(viewModel.primaryStateTitle, "Modelo requerido")
    }

    func testDownloadingModelState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .downloading(progress: 0.4), session: .idle, error: nil)

        XCTAssertEqual(viewModel.primaryState, .downloadingModel)
        XCTAssertEqual(viewModel.primaryStateTitle, "Descargando modelo...")
    }

    func testAccessibilityRequiredState() {
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        viewModel.transcript = ""
        viewModel.hotkeyStatus = .accessibilityPermissionRequired

        XCTAssertEqual(viewModel.primaryState, .accessibilityRequired)
        XCTAssertEqual(viewModel.primaryStateTitle, "Permiso de Accesibilidad requerido")
    }

    func testErrorStateTakesPriorityOverEverythingElse() {
        let viewModel = DictationViewModel()
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
        let viewModel = DictationViewModel()
        viewModel.state = AppState(permission: .denied, model: .missing, session: .recording, error: nil)

        XCTAssertEqual(viewModel.primaryState, .recording)
        XCTAssertEqual(viewModel.primaryStateTitle, "Grabando...")
    }
}
