import XCTest
@testable import LocalDictate

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
