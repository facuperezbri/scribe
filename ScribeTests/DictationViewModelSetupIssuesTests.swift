import XCTest
@testable import Scribe

@MainActor
final class DictationViewModelSetupIssuesTests: XCTestCase {
    private let defaultsSuiteName = "DictationViewModelSetupIssuesTests"

    private func makeUserDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private func makeViewModel(
        modelInstalled: Bool = true,
        permissionStatus: MicrophonePermissionStatus = .authorized,
        hotkeyStatus: HotkeyStatus = .active,
        autoPasteEnabled: Bool = true,
        accessibilityGranted: Bool = true,
        formattingEnabled: Bool? = nil,
        appleIntelligenceAvailable: Bool = true,
        userDefaults: UserDefaults? = nil
    ) -> DictationViewModel {
        let defaults = userDefaults ?? makeUserDefaults()
        if !autoPasteEnabled {
            defaults.set(true, forKey: "Scribe.hasDisabledAutoPaste")
        }
        if let formattingEnabled {
            defaults.set(!formattingEnabled, forKey: "Scribe.hasDisabledFormatting")
        }

        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = modelInstalled
        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = permissionStatus
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = hotkeyStatus
        let controller = PermissionStatusController(
            microphonePermissionManager: permissionManager,
            isAccessibilityPermissionGranted: { accessibilityGranted }
        )
        let appleIntelligenceController = AppleIntelligenceAvailabilityController(
            unavailableReasonProvider: { appleIntelligenceAvailable ? nil : .appleIntelligenceNotEnabled }
        )

        return DictationViewModel(
            audioRecorder: FakeAudioRecordingService(),
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            globalHotkeyService: hotkeyService,
            windowActivationService: FakeWindowActivationService(),
            autoPasteService: FakeAutoPasteService(),
            transcriptionService: FakeTranscriptionService(),
            permissionStatusController: controller,
            appleIntelligenceAvailabilityController: appleIntelligenceController,
            userDefaults: defaults
        )
    }

    func testNoSetupIssuesWhenEverythingReady() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.setupIssues.isEmpty)
    }

    func testMissingModelIsReported() {
        let viewModel = makeViewModel(modelInstalled: false)
        XCTAssertEqual(viewModel.setupIssues, [.missingModel])
    }

    func testInputMonitoringIssueIsReported() {
        let viewModel = makeViewModel(hotkeyStatus: .inputMonitoringPermissionRequired)
        XCTAssertTrue(viewModel.setupIssues.contains(.inputMonitoringRequired))
    }

    func testAccessibilityIssueOnlyWhenAutoPasteEnabled() {
        let disabled = makeViewModel(autoPasteEnabled: false, accessibilityGranted: false)
        XCTAssertFalse(disabled.setupIssues.contains(.accessibilityRequired))

        let enabled = makeViewModel(autoPasteEnabled: true, accessibilityGranted: false)
        XCTAssertTrue(enabled.setupIssues.contains(.accessibilityRequired))
    }

    func testAppleIntelligenceIssueOnlyWhenFormattingEnabled() {
        let disabled = makeViewModel(formattingEnabled: false, appleIntelligenceAvailable: false)
        XCTAssertFalse(disabled.setupIssues.contains(.appleIntelligenceUnavailable))

        let enabled = makeViewModel(formattingEnabled: true, appleIntelligenceAvailable: false)
        XCTAssertTrue(enabled.setupIssues.contains(.appleIntelligenceUnavailable))
    }

    func testNoAppleIntelligenceIssueWhenFormattingEnabledAndAvailable() {
        let viewModel = makeViewModel(formattingEnabled: true, appleIntelligenceAvailable: true)
        XCTAssertFalse(viewModel.setupIssues.contains(.appleIntelligenceUnavailable))
    }

    func testRefreshSystemPermissionsUpdatesAccessibilityFlag() {
        var granted = false
        let permissionManager = FakeMicrophonePermissionManager()
        let controller = PermissionStatusController(
            microphonePermissionManager: permissionManager,
            isAccessibilityPermissionGranted: { granted }
        )
        let viewModel = DictationViewModel(
            audioRecorder: FakeAudioRecordingService(),
            modelManager: FakeModelManager(),
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            globalHotkeyService: FakeGlobalHotkeyService(),
            windowActivationService: FakeWindowActivationService(),
            autoPasteService: FakeAutoPasteService(),
            transcriptionService: FakeTranscriptionService(),
            permissionStatusController: controller,
            appleIntelligenceAvailabilityController: AppleIntelligenceAvailabilityController(unavailableReasonProvider: { .appleIntelligenceNotEnabled }),
            userDefaults: makeUserDefaults()
        )

        XCTAssertFalse(viewModel.isAccessibilityPermissionGranted)
        granted = true
        viewModel.refreshSystemPermissions()
        XCTAssertTrue(viewModel.isAccessibilityPermissionGranted)
    }
}
