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

    // MARK: - LiveAutoPasteService.paste

    /// Todos los efectos de sistema (portapapeles, reactivación, evento de teclado) están
    /// inyectados como espías locales: ninguna de estas pruebas toca el portapapeles real, activa
    /// una app real, ni sintetiza una tecla real. Clase (no struct) porque los closures inyectados
    /// la capturan por referencia para registrar llamadas. `changeCount` imita el contador real de
    /// `NSPasteboard`: la fake de `writeToPasteboard` lo incrementa al escribir, así que las
    /// pruebas de restauración pueden simular una escritura externa (p. ej. el usuario copiando
    /// algo nuevo) incrementándolo de nuevo entre la síntesis de ⌘V y el chequeo final.
    private final class PasteSpies {
        var pasteboardWriteCallCount = 0
        var activateCallCount = 0
        var keystrokeCallCount = 0
        var readPasteboardCallCount = 0
        var restoreCallCount = 0
        var lastRestoredText: String?
        var changeCount = 0
    }

    private func makeService(
        frontmostApplication: NSRunningApplication?,
        accessibilityGranted: Bool = true,
        secureField: Bool = false,
        previousClipboardText: String? = "clipboard anterior",
        pasteboardWriteSucceeds: Bool = true,
        keystrokeSucceeds: Bool = true,
        externalClipboardChangeAfterOurWrite: Bool = false,
        spies: PasteSpies
    ) -> LiveAutoPasteService {
        LiveAutoPasteService(
            frontmostApplicationProvider: { frontmostApplication },
            ownBundleIdentifier: "com.example.not-scribe",
            isAccessibilityPermissionGranted: { accessibilityGranted },
            isFocusedElementSecure: { secureField },
            readPasteboardString: {
                spies.readPasteboardCallCount += 1
                return previousClipboardText
            },
            writeToPasteboard: { _ in
                spies.pasteboardWriteCallCount += 1
                if pasteboardWriteSucceeds { spies.changeCount += 1 }
                return pasteboardWriteSucceeds
            },
            pasteboardChangeCount: { spies.changeCount },
            restorePasteboardString: { text in
                spies.restoreCallCount += 1
                spies.lastRestoredText = text
            },
            activateTarget: { _ in spies.activateCallCount += 1 },
            postPasteKeystroke: {
                spies.keystrokeCallCount += 1
                if externalClipboardChangeAfterOurWrite { spies.changeCount += 1 }
                return keystrokeSucceeds
            }
        )
    }

    func testPasteReturnsEmptyTextWithoutAnySideEffect() async {
        let spies = PasteSpies()
        let service = makeService(frontmostApplication: .current, spies: spies)

        let result = await service.paste(text: "", target: .fake())

        XCTAssertEqual(result, .emptyText)
        XCTAssertEqual(spies.pasteboardWriteCallCount, 0)
        XCTAssertEqual(spies.activateCallCount, 0)
        XCTAssertEqual(spies.keystrokeCallCount, 0)
        XCTAssertEqual(spies.readPasteboardCallCount, 0)
        XCTAssertEqual(spies.restoreCallCount, 0)
    }

    func testPasteReturnsAccessibilityPermissionMissingWithoutTouchingThePasteboard() async {
        let spies = PasteSpies()
        let service = makeService(frontmostApplication: .current, accessibilityGranted: false, spies: spies)

        let result = await service.paste(text: "hola", target: .fake())

        XCTAssertEqual(result, .accessibilityPermissionMissing)
        XCTAssertEqual(spies.pasteboardWriteCallCount, 0)
        XCTAssertEqual(spies.readPasteboardCallCount, 0)
        XCTAssertEqual(spies.restoreCallCount, 0)
    }

    func testPasteReturnsSecureFieldWithoutTouchingThePasteboard() async {
        let spies = PasteSpies()
        let service = makeService(frontmostApplication: .current, secureField: true, spies: spies)

        let result = await service.paste(text: "hola", target: .fake())

        XCTAssertEqual(result, .secureField)
        XCTAssertEqual(spies.pasteboardWriteCallCount, 0)
        XCTAssertEqual(spies.readPasteboardCallCount, 0)
        XCTAssertEqual(spies.restoreCallCount, 0)
    }

    /// Aun cuando la escritura falla, `writeStringToGeneralPasteboard` ya limpió el portapapeles
    /// antes de intentar escribir — se restaura el contenido anterior igual, para no dejar el
    /// portapapeles del usuario vacío por un intento fallido.
    func testPasteReturnsPasteboardFailedWithoutSendingAKeystrokeButRestoresTheClipboard() async {
        let spies = PasteSpies()
        let service = makeService(
            frontmostApplication: .current,
            previousClipboardText: "clipboard anterior",
            pasteboardWriteSucceeds: false,
            spies: spies
        )

        let result = await service.paste(text: "hola", target: .fake())

        XCTAssertEqual(result, .pasteboardFailed)
        XCTAssertEqual(spies.keystrokeCallCount, 0)
        XCTAssertEqual(spies.restoreCallCount, 1)
        XCTAssertEqual(spies.lastRestoredText, "clipboard anterior")
    }

    func testPasteReturnsEventPostFailedWhenKeystrokeSynthesisFailsButStillRestoresTheClipboard() async {
        let spies = PasteSpies()
        let service = makeService(
            frontmostApplication: .current,
            previousClipboardText: "clipboard anterior",
            keystrokeSucceeds: false,
            spies: spies
        )

        let result = await service.paste(text: "hola", target: .fake())

        XCTAssertEqual(result, .eventPostFailed)
        XCTAssertEqual(spies.pasteboardWriteCallCount, 1)
        XCTAssertEqual(spies.restoreCallCount, 1)
        XCTAssertEqual(spies.lastRestoredText, "clipboard anterior")
    }

    /// Caso común de background-first: el destino nunca perdió el foco, así que no hace falta
    /// reactivarlo antes de sintetizar ⌘V.
    func testPasteSkipsReactivationWhenTargetIsAlreadyFrontmost() async {
        let spies = PasteSpies()
        let target = AutoPasteTarget.fake()
        let service = makeService(frontmostApplication: target.runningApplication, spies: spies)

        let result = await service.paste(text: "hola", target: target)

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(spies.activateCallCount, 0)
        XCTAssertEqual(spies.keystrokeCallCount, 1)
        XCTAssertEqual(spies.restoreCallCount, 1)
    }

    /// El usuario cambió de foco durante la transcripción: hay que reactivar el destino capturado
    /// antes de pegar, no pegar en lo que esté al frente en ese momento (ver `docs/DECISIONS.md`).
    func testPasteReactivatesTargetWhenItIsNoLongerFrontmost() async {
        let spies = PasteSpies()
        let target = AutoPasteTarget.fake(processIdentifier: 999_999)
        let service = makeService(frontmostApplication: .current, spies: spies)

        let result = await service.paste(text: "hola", target: target)

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(spies.activateCallCount, 1)
        XCTAssertEqual(spies.keystrokeCallCount, 1)
        XCTAssertEqual(spies.restoreCallCount, 1)
    }

    // MARK: - LiveAutoPasteService.paste — restauración del portapapeles (Fase 5)

    /// Camino feliz: después de pegar, el portapapeles vuelve a tener lo que tenía antes del
    /// auto-paste, no el texto transcripto.
    func testPasteRestoresThePreviousClipboardContentsAfterPasting() async {
        let spies = PasteSpies()
        let service = makeService(
            frontmostApplication: .current,
            previousClipboardText: "lo que el usuario había copiado antes",
            spies: spies
        )

        let result = await service.paste(text: "hola mundo", target: .fake())

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(spies.readPasteboardCallCount, 1)
        XCTAssertEqual(spies.restoreCallCount, 1)
        XCTAssertEqual(spies.lastRestoredText, "lo que el usuario había copiado antes")
    }

    /// Si no había nada de texto plano en el portapapeles antes del auto-paste, "restaurar"
    /// significa dejarlo vacío, no dejar la transcripción pegada ahí.
    func testPasteRestoresAnEmptyClipboardWhenTherePreviouslyWasNothing() async {
        let spies = PasteSpies()
        let service = makeService(
            frontmostApplication: .current,
            previousClipboardText: nil,
            spies: spies
        )

        let result = await service.paste(text: "hola mundo", target: .fake())

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(spies.restoreCallCount, 1)
        XCTAssertNil(spies.lastRestoredText)
    }

    /// Si algo escribió en el portapapeles entre el auto-paste y la restauración (el caso
    /// esperado: el usuario copió algo nuevo mientras esperaba), no se pisa esa copia más
    /// reciente con el contenido de antes del auto-paste.
    func testPasteDoesNotRestoreWhenTheClipboardChangedDuringTheRestoreWindow() async {
        let spies = PasteSpies()
        let service = makeService(
            frontmostApplication: .current,
            previousClipboardText: "clipboard anterior",
            externalClipboardChangeAfterOurWrite: true,
            spies: spies
        )

        let result = await service.paste(text: "hola mundo", target: .fake())

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(spies.restoreCallCount, 0)
    }
}
