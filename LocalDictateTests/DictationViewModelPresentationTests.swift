import XCTest
@testable import LocalDictate

/// Cubre la lógica de presentación pura de `DictationViewModel` (funciones de `state` y
/// `recordingElapsed` sin dependencias externas), no el flujo de grabación/transcripción real.
@MainActor
final class DictationViewModelPresentationTests: XCTestCase {
    func testRecordButtonTitleReflectsState() {
        let viewModel = DictationViewModel()

        viewModel.state.session = .idle
        XCTAssertEqual(viewModel.recordButtonTitle, "Grabar")

        viewModel.state.session = .recording
        XCTAssertEqual(viewModel.recordButtonTitle, "Detener")

        viewModel.state.session = .stoppingRecording
        XCTAssertEqual(viewModel.recordButtonTitle, "Deteniendo...")
    }

    func testStatusKindForEachState() {
        let viewModel = DictationViewModel()

        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        XCTAssertEqual(viewModel.statusKind, .neutral)

        viewModel.state.session = .recording
        XCTAssertEqual(viewModel.statusKind, .active)

        viewModel.state = AppState(permission: .authorized, model: .missing, session: .idle, error: nil)
        XCTAssertEqual(viewModel.statusKind, .warning)

        viewModel.state = AppState(permission: .denied, model: .installed, session: .idle, error: nil)
        XCTAssertEqual(viewModel.statusKind, .error)

        viewModel.state = AppState(
            permission: .authorized,
            model: .installed,
            session: .idle,
            error: AppError(category: .unknown, message: "boom")
        )
        XCTAssertEqual(viewModel.statusKind, .error)
    }

    func testIsErrorOnlyForErrorStates() {
        let viewModel = DictationViewModel()

        viewModel.state = AppState(
            permission: .authorized,
            model: .installed,
            session: .idle,
            error: AppError(category: .unknown, message: "boom")
        )
        XCTAssertTrue(viewModel.isError)

        viewModel.state = AppState(permission: .denied, model: .installed, session: .idle, error: nil)
        XCTAssertTrue(viewModel.isError)

        viewModel.state = AppState(permission: .authorized, model: .installed, session: .idle, error: nil)
        XCTAssertFalse(viewModel.isError)
    }

    func testIsBusyForTransientStates() {
        let viewModel = DictationViewModel()

        for busySession: DictationSessionState in [.transcribing, .requestingPermission, .stoppingRecording] {
            viewModel.state.session = busySession
            XCTAssertTrue(viewModel.isBusy, "\(busySession) debería considerarse ocupado")
        }

        viewModel.state.session = .idle
        viewModel.state.model = .downloading(progress: 0.5)
        XCTAssertTrue(viewModel.isBusy, "descargar el modelo debería considerarse ocupado")
        viewModel.state.model = .installed

        for idleSession: DictationSessionState in [.idle, .recording] {
            viewModel.state.session = idleSession
            XCTAssertFalse(viewModel.isBusy, "\(idleSession) no debería considerarse ocupado")
        }
    }

    func testRecordingWarningThresholds() {
        let viewModel = DictationViewModel()
        viewModel.state.session = .recording

        viewModel.recordingElapsed = 10
        XCTAssertNil(viewModel.recordingWarningText)
        XCTAssertFalse(viewModel.isStrongRecordingWarning)

        viewModel.recordingElapsed = 130
        XCTAssertNotNil(viewModel.recordingWarningText)
        XCTAssertFalse(viewModel.isStrongRecordingWarning)

        viewModel.recordingElapsed = 310
        XCTAssertNotNil(viewModel.recordingWarningText)
        XCTAssertTrue(viewModel.isStrongRecordingWarning)
    }

    func testRecordingWarningOnlyAppliesWhileRecording() {
        let viewModel = DictationViewModel()
        viewModel.state.session = .idle
        viewModel.recordingElapsed = 400

        XCTAssertNil(viewModel.recordingWarningText)
        XCTAssertFalse(viewModel.isStrongRecordingWarning)
    }
}
