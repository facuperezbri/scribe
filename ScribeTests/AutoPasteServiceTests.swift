import XCTest
@testable import Scribe

/// Cubre `AutoPasteServicing` en aislamiento, sin depender de `DictationViewModel`: la captura de
/// destino y el pegado en sí son responsabilidad exclusiva de este servicio (ver
/// `docs/DECISIONS.md`), así que sus reglas (excluir a Scribe, registrar llamadas) se prueban acá
/// directamente.
final class AutoPasteServiceTests: XCTestCase {
    func testFakeAutoPasteServiceReturnsConfiguredTarget() {
        let service = FakeAutoPasteService()
        service.targetToCapture = .fake(bundleIdentifier: "com.example.notes")

        let target = service.captureTarget()

        XCTAssertEqual(target?.bundleIdentifier, "com.example.notes")
        XCTAssertEqual(service.captureTargetCallCount, 1)
    }

    func testFakeAutoPasteServiceReturnsNilWhenNoTargetConfigured() {
        let service = FakeAutoPasteService()

        XCTAssertNil(service.captureTarget())
        XCTAssertEqual(service.captureTargetCallCount, 1)
    }

    func testFakeAutoPasteServiceRecordsPasteCallsAndReturnsConfiguredResult() async {
        let service = FakeAutoPasteService()
        service.pasteResult = .accessibilityPermissionMissing
        let target = AutoPasteTarget.fake()

        let result = await service.paste(text: "hola mundo", target: target)

        XCTAssertEqual(result, .accessibilityPermissionMissing)
        XCTAssertEqual(service.pasteCallCount, 1)
        XCTAssertEqual(service.lastPastedText, "hola mundo")
        XCTAssertEqual(service.lastPasteTarget, target)
    }

    func testLiveAutoPasteServiceExcludesItsOwnBundleIdentifier() {
        let scribe = NSRunningApplication.current
        let service = LiveAutoPasteService(
            frontmostApplicationProvider: { scribe },
            ownBundleIdentifier: scribe.bundleIdentifier
        )

        XCTAssertNil(service.captureTarget())
    }

    func testLiveAutoPasteServiceCapturesAFrontmostAppThatIsNotItself() {
        let otherApp = NSRunningApplication.current
        let service = LiveAutoPasteService(
            frontmostApplicationProvider: { otherApp },
            ownBundleIdentifier: "com.example.not-scribe"
        )

        let target = service.captureTarget()

        XCTAssertEqual(target?.processIdentifier, otherApp.processIdentifier)
        XCTAssertEqual(target?.bundleIdentifier, otherApp.bundleIdentifier)
    }

    func testLiveAutoPasteServiceReturnsNilWithoutAFrontmostApp() {
        let service = LiveAutoPasteService(
            frontmostApplicationProvider: { nil },
            ownBundleIdentifier: "com.example.not-scribe"
        )

        XCTAssertNil(service.captureTarget())
    }

    func testLiveAutoPasteServicePasteIsAPlaceholderUntilPhase4() async {
        let service = LiveAutoPasteService(
            frontmostApplicationProvider: { nil },
            ownBundleIdentifier: "com.example.not-scribe"
        )

        let result = await service.paste(text: "hola", target: .fake())

        XCTAssertEqual(result, .unknown)
    }
}
