import XCTest
@testable import Scribe

@MainActor
final class DictationViewModelOnboardingTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DictationViewModelOnboardingTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    private func makeViewModel() -> DictationViewModel {
        DictationViewModel(globalHotkeyService: FakeGlobalHotkeyService(), userDefaults: userDefaults)
    }

    func testShowsOnboardingWelcomeWhenNeverDismissedBefore() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.showOnboardingWelcome)
    }

    func testDoesNotShowOnboardingWelcomeWhenAlreadyDismissedBefore() {
        userDefaults.set(true, forKey: "Scribe.hasSeenOnboardingWelcome")

        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.showOnboardingWelcome)
    }

    func testDismissingOnboardingWelcomeHidesItAndPersistsTheChoice() {
        let viewModel = makeViewModel()

        viewModel.dismissOnboardingWelcome()

        XCTAssertFalse(viewModel.showOnboardingWelcome)
        XCTAssertTrue(userDefaults.bool(forKey: "Scribe.hasSeenOnboardingWelcome"))
    }
}
