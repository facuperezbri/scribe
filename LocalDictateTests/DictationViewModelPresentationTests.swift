import XCTest
@testable import LocalDictate

/// Cubre la lógica de presentación pura de `DictationViewModel` (funciones de `state` y
/// `recordingElapsed` sin dependencias externas), no el flujo de grabación/transcripción real.
@MainActor
final class DictationViewModelPresentationTests: XCTestCase {
    func testRecordButtonTitleReflectsState() {
        let viewModel = DictationViewModel()

        viewModel.state = .ready
        XCTAssertEqual(viewModel.recordButtonTitle, "Grabar")

        viewModel.state = .recording
        XCTAssertEqual(viewModel.recordButtonTitle, "Detener")

        viewModel.state = .stoppingRecording
        XCTAssertEqual(viewModel.recordButtonTitle, "Deteniendo...")
    }

    func testStatusKindForEachState() {
        let viewModel = DictationViewModel()

        viewModel.state = .ready
        XCTAssertEqual(viewModel.statusKind, .neutral)

        viewModel.state = .transcriptReady
        XCTAssertEqual(viewModel.statusKind, .neutral)

        viewModel.state = .recording
        XCTAssertEqual(viewModel.statusKind, .active)

        viewModel.state = .missingModel
        XCTAssertEqual(viewModel.statusKind, .warning)

        viewModel.state = .microphonePermissionDenied
        XCTAssertEqual(viewModel.statusKind, .error)

        viewModel.state = .error(AppError(category: .unknown, message: "boom"))
        XCTAssertEqual(viewModel.statusKind, .error)
    }

    func testIsErrorOnlyForErrorStates() {
        let viewModel = DictationViewModel()

        viewModel.state = .error(AppError(category: .unknown, message: "boom"))
        XCTAssertTrue(viewModel.isError)

        viewModel.state = .microphonePermissionDenied
        XCTAssertTrue(viewModel.isError)

        viewModel.state = .ready
        XCTAssertFalse(viewModel.isError)
    }

    func testIsBusyForTransientStates() {
        let viewModel = DictationViewModel()

        for busyState: AppState in [.transcribing, .downloadingModel, .requestingPermission, .stoppingRecording] {
            viewModel.state = busyState
            XCTAssertTrue(viewModel.isBusy, "\(busyState) debería considerarse ocupado")
        }

        for idleState: AppState in [.ready, .recording, .transcriptReady, .missingModel] {
            viewModel.state = idleState
            XCTAssertFalse(viewModel.isBusy, "\(idleState) no debería considerarse ocupado")
        }
    }

    func testRecordingWarningThresholds() {
        let viewModel = DictationViewModel()
        viewModel.state = .recording

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
        viewModel.state = .ready
        viewModel.recordingElapsed = 400

        XCTAssertNil(viewModel.recordingWarningText)
        XCTAssertFalse(viewModel.isStrongRecordingWarning)
    }
}
