import XCTest
@testable import Scribe

final class RecordingDurationPolicyTests: XCTestCase {
    func testNoWarningBelowSoftThreshold() {
        XCTAssertEqual(RecordingDurationPolicy.warning(forElapsed: 0), .none)
        XCTAssertEqual(RecordingDurationPolicy.warning(forElapsed: RecordingDurationPolicy.softThreshold - 1), .none)
    }

    func testSoftWarningBetweenThresholds() {
        XCTAssertEqual(RecordingDurationPolicy.warning(forElapsed: RecordingDurationPolicy.softThreshold), .soft)
        XCTAssertEqual(RecordingDurationPolicy.warning(forElapsed: RecordingDurationPolicy.strongThreshold - 1), .soft)
    }

    func testStrongWarningAtOrAboveStrongThreshold() {
        XCTAssertEqual(RecordingDurationPolicy.warning(forElapsed: RecordingDurationPolicy.strongThreshold), .strong)
        XCTAssertEqual(RecordingDurationPolicy.warning(forElapsed: RecordingDurationPolicy.strongThreshold + 500), .strong)
    }
}
