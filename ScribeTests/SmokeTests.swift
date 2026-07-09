import XCTest
@testable import Scribe

final class SmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testDictationViewModelCanBeInstantiated() {
        let viewModel = DictationViewModel()
        XCTAssertNotNil(viewModel)
    }
}
