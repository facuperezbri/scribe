import XCTest
@testable import Scribe

final class PermissionStatusControllerTests: XCTestCase {
    func testCurrentStatusForwardsTheUnderlyingManager() {
        let manager = FakeMicrophonePermissionManager()
        manager.status = .denied
        let controller = PermissionStatusController(microphonePermissionManager: manager)

        XCTAssertEqual(controller.currentStatus, .denied)
    }

    func testRequestAccessForwardsTheUnderlyingManager() async {
        let manager = FakeMicrophonePermissionManager()
        manager.requestAccessResult = false
        let controller = PermissionStatusController(microphonePermissionManager: manager)

        let granted = await controller.requestAccess()

        XCTAssertFalse(granted)
    }
}
