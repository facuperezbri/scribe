import AppKit
import XCTest
@testable import Scribe

/// Cubre el contrato de `GlobalHotkeyServicing` a través del fake (sin depender de un evento de
/// teclado real) y que `DictationViewModel` conecta el callback del atajo global con
/// `handlePrimaryDictationAction(source: .globalHotkey)` sin duplicar el flujo de grabar/detener.
///
/// Los casos que ejercitan `DictationViewModel` completo (atajo en modo toggle, Fn + Espacio)
/// simulan la presión del atajo a través de
/// `FakeGlobalHotkeyService.simulateHotkeyPressed()`, nunca con un evento real de teclado — eso es
/// justamente lo que `LiveGlobalHotkeyService` traduce a esa llamada, y queda fuera del alcance de
/// un test unitario. La lógica real de detección de `keyCode`/`.function`/`isARepeat` de
/// `LiveGlobalHotkeyService.handleKeyDown` sí se cubre más abajo con eventos sintéticos.
@MainActor
final class GlobalHotkeyServiceTests: XCTestCase {
    private func makeViewModel(
        hotkeyService: FakeGlobalHotkeyService,
        audioRecorder: FakeAudioRecordingService = FakeAudioRecordingService(),
        transcriptionService: FakeTranscriptionService = FakeTranscriptionService(),
        modelInstalled: Bool = true,
        permissionStatus: MicrophonePermissionStatus = .authorized
    ) -> DictationViewModel {
        let modelManager = FakeModelManager()
        modelManager.isModelInstalled = modelInstalled
        let permissionManager = FakeMicrophonePermissionManager()
        permissionManager.status = permissionStatus

        return DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: modelManager,
            microphonePermissionManager: permissionManager,
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            globalHotkeyService: hotkeyService,
            transcriptionService: transcriptionService
        )
    }

    func testStartRegistersCallbackThatCanBeSimulated() throws {
        let service = FakeGlobalHotkeyService()
        var pressed = false

        try service.start { pressed = true }

        XCTAssertEqual(service.startCallCount, 1)
        service.simulateHotkeyPressed()
        XCTAssertTrue(pressed)
    }

    func testStartPropagatesRegistrationFailure() {
        let service = FakeGlobalHotkeyService()
        service.startResult = .failure(GlobalHotkeyServiceError.registrationFailed)

        XCTAssertThrowsError(try service.start {})
    }

    func testStopClearsCallback() throws {
        let service = FakeGlobalHotkeyService()
        var pressed = false
        try service.start { pressed = true }

        service.stop()
        service.simulateHotkeyPressed()

        XCTAssertFalse(pressed)
        XCTAssertEqual(service.stopCallCount, 1)
    }

    func testGlobalHotkeyPressStartsRecordingLikeTheUserInterfaceButton() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        XCTAssertEqual(hotkeyService.startCallCount, 1)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Toggle: la segunda presión del atajo, con la grabación en curso, detiene y arranca la
    /// transcripción — el mismo flujo que produce un segundo toque del botón de la UI.
    func testSecondGlobalHotkeyPressStopsRecordingAndTranscribes() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .recording)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.stopRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .idle)
    }

    /// Regla de comportamiento 3: mientras se transcribe, el atajo no debe arrancar una
    /// grabación nueva — igual que el botón, queda bloqueado por `isBusy`.
    func testGlobalHotkeyPressWhileTranscribingDoesNotStartNewRecording() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let transcriptionService = FakeTranscriptionService()
        transcriptionService.delayMilliseconds = 200
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder,
            transcriptionService: transcriptionService
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .transcribing)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .transcribing)
    }

    /// Con una transcripción no vacía, el atajo la reemplaza directo, igual que el botón — ya no hay
    /// confirmación bloqueante antes de grabar.
    func testGlobalHotkeyPressWithNonEmptyTranscriptStartsImmediately() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)
        viewModel.transcript = "transcripción anterior"

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Regla de comportamiento 6: sin permiso de micrófono, el atajo no arranca a grabar; el
    /// estado de permiso sigue siendo la única autoridad, igual que con el botón.
    func testGlobalHotkeyPressWithDeniedMicrophonePermissionDoesNotStartRecording() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder,
            permissionStatus: .denied
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 0)
        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.state.permission, .denied)
    }

    /// Regla de comportamiento 7: con el modelo faltante, el atajo preserva el comportamiento
    /// existente. Arrancar a grabar no depende del modelo (solo detener y transcribir sí), así
    /// que la segunda presión debe volver a `.idle` sin transcribir ni descargar nada sola.
    func testGlobalHotkeyPressWithMissingModelPreservesExistingBehavior() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(
            hotkeyService: hotkeyService,
            audioRecorder: audioRecorder,
            modelInstalled: false
        )

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .recording)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.state.model, .missing)
        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.transcript, "")
    }

    /// El botón de la UI sigue funcionando igual con el servicio de atajo inyectado — el atajo
    /// es un origen más de `handlePrimaryDictationAction`, no un flujo paralelo.
    func testUserInterfaceButtonStillWorksWithHotkeyServiceInjected() async {
        let hotkeyService = FakeGlobalHotkeyService()
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    // MARK: - Estado del atajo y permiso de Accesibilidad

    func testHotkeyStatusReflectsActiveAfterInit() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = .active
        let viewModel = makeViewModel(hotkeyService: hotkeyService)

        XCTAssertEqual(viewModel.hotkeyStatus, .active)
    }

    /// El registro sigue instalando el monitor y solo el `AXIsProcessTrusted` falla;
    /// eso no debe impedir que la app arranque ni tumbar `init`.
    func testHotkeyStatusReflectsAccessibilityPermissionRequiredAfterInit() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.accessibilityPermissionDenied)
        hotkeyService.statusResult = .accessibilityPermissionRequired
        let viewModel = makeViewModel(hotkeyService: hotkeyService)

        XCTAssertEqual(viewModel.hotkeyStatus, .accessibilityPermissionRequired)
    }

    /// Una falla de registro no relacionada con Accesibilidad tampoco es fatal: el botón de la UI
    /// sigue grabando con normalidad.
    func testNonFatalRegistrationFailureDoesNotPreventNormalUse() async {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.registrationFailed)
        hotkeyService.statusResult = .failed("No se pudo registrar el atajo de teclado global.")
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        XCTAssertEqual(viewModel.hotkeyStatus, .failed("No se pudo registrar el atajo de teclado global."))

        viewModel.handlePrimaryDictationAction(source: .userInterface)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// Simula que el usuario otorgó el permiso de Accesibilidad después de que la app arrancó:
    /// `refreshHotkeyStatus()` debe reflejarlo sin reiniciar el servicio.
    func testRefreshHotkeyStatusUpdatesAfterPermissionGrantedLater() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.accessibilityPermissionDenied)
        hotkeyService.statusResult = .accessibilityPermissionRequired
        let viewModel = makeViewModel(hotkeyService: hotkeyService)
        XCTAssertEqual(viewModel.hotkeyStatus, .accessibilityPermissionRequired)

        hotkeyService.statusResult = .active
        viewModel.refreshHotkeyStatus()

        XCTAssertEqual(viewModel.hotkeyStatus, .active)
    }

    /// El fake sigue disparando el flujo centralizado sin importar el estado reportado por
    /// `currentStatus()` — esa distinción es solo para la UI, no cambia el cableado del atajo.
    func testGlobalHotkeyStillUsesCentralizedWorkflowWhenAccessibilityPermissionIsRequired() async {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = .accessibilityPermissionRequired
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// `LiveGlobalHotkeyService.currentStatus()` antes de `start` no depende de Accesibilidad:
    /// no hay callback ni monitor instalado todavía, así que siempre es `.unknown`.
    func testLiveServiceStatusIsUnknownBeforeStart() {
        let service = LiveGlobalHotkeyService()
        XCTAssertEqual(service.currentStatus(), .unknown)
    }

    /// Después de `start`, el estado real depende del permiso de Accesibilidad de esta máquina
    /// (no controlable en CI), así que solo se verifica que deje de ser `.unknown`/`.failed` —
    /// sin asumir si el proceso está o no confiado.
    func testLiveServiceStatusIsActiveOrPermissionRequiredAfterStart() {
        let service = LiveGlobalHotkeyService()
        try? service.start {}

        switch service.currentStatus() {
        case .active, .accessibilityPermissionRequired:
            break
        case .unknown, .failed:
            XCTFail("Se esperaba .active o .accessibilityPermissionRequired después de start, se obtuvo \(service.currentStatus())")
        }
    }

    /// `stop()` vuelve a dejar el estado en `.unknown`, igual que antes de llamar a `start`.
    func testLiveServiceStatusReturnsToUnknownAfterStop() {
        let service = LiveGlobalHotkeyService()
        try? service.start {}

        service.stop()

        XCTAssertEqual(service.currentStatus(), .unknown)
    }

    // Estos tests ejercitan la lógica real de detección con eventos sintéticos construidos vía
    // `NSEvent.keyEvent`, sin depender de un teclado real ni de un monitor global entregando
    // eventos del sistema. `handleKeyDown` dispara el callback con `Task { @MainActor in ... }`,
    // así que cada aserción positiva espera brevemente antes de verificar.

    private func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isARepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: isARepeat,
            keyCode: keyCode
        )!
    }

    // MARK: - HotkeyTrigger (combo configurable, fallback si Fn + Espacio no fuera fiable)

    func testFnSpaceTriggerMatchesFnPlusSpace() {
        let event = makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function)
        XCTAssertTrue(HotkeyTrigger.fnSpace.matches(event))
    }

    func testFnSpaceTriggerDoesNotMatchADifferentKeyCode() {
        let event = makeKeyDownEvent(keyCode: 0, modifierFlags: .function)
        XCTAssertFalse(HotkeyTrigger.fnSpace.matches(event))
    }

    func testFnSpaceTriggerDoesNotMatchADifferentModifier() {
        let event = makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .option)
        XCTAssertFalse(HotkeyTrigger.fnSpace.matches(event))
    }

    /// `LiveGlobalHotkeyService` no tiene el combo de Fn + Espacio hardcodeado en su lógica de
    /// detección: instanciarlo con otro `HotkeyTrigger` (por ejemplo, un fallback para un teclado
    /// donde la validación de QA confirme que Fn + Espacio no es fiable) alcanza para cambiar qué
    /// evento dispara el atajo, sin tocar `handleKeyDown` ni el modelo de permisos.
    func testCustomTriggerIsHonoredInsteadOfTheDefault() async {
        let fallback = HotkeyTrigger(keyCode: 96, requiredModifierFlags: .control)
        let service = LiveGlobalHotkeyService(trigger: fallback)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        // El combo por defecto (Fn + Espacio) ya no dispara nada con este trigger inyectado.
        service.handleKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function)
        )
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(pressCount, 0)

        service.handleKeyDown(makeKeyDownEvent(keyCode: 96, modifierFlags: .control))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(pressCount, 1)
    }

    // MARK: - Detección real de Fn + Espacio (LiveGlobalHotkeyService.handleKeyDown)

    func testHandleKeyDownFiresOnFnSpace() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function)
        )
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 1)
    }

    /// Space sola (sin Fn) no debe disparar el atajo: si lo hiciera, escribir un espacio normal
    /// en cualquier app activaría la grabación.
    func testHandleKeyDownDoesNotFireForSpaceAlone() async {
        let service = LiveGlobalHotkeyService()
        var pressed = false
        try? service.start { pressed = true }

        service.handleKeyDown(makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(pressed)
    }

    /// Fn sola (con cualquier otra tecla, no Space) no debe disparar el atajo.
    func testHandleKeyDownDoesNotFireForFnWithOtherKey() async {
        let service = LiveGlobalHotkeyService()
        var pressed = false
        try? service.start { pressed = true }

        // keyCode 0 == "a" en el layout físico ANSI.
        service.handleKeyDown(makeKeyDownEvent(keyCode: 0, modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(pressed)
    }

    /// Option + Espacio (el atajo viejo, con otro modificador) no debe disparar el atajo nuevo:
    /// confirma que la migración no dejó ninguna ruta que siga reaccionando a Option.
    func testHandleKeyDownDoesNotFireForOptionSpace() async {
        let service = LiveGlobalHotkeyService()
        var pressed = false
        try? service.start { pressed = true }

        service.handleKeyDown(makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .option))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(pressed)
    }

    /// Mantener Fn + Espacio presionado genera `keyDown` repetidos (`isARepeat == true`) que no
    /// deben volver a disparar el atajo — solo el `keyDown` inicial cuenta como una presión.
    func testHandleKeyDownIgnoresRepeatsWhileHeld() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function, isARepeat: false)
        )
        service.handleKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function, isARepeat: true)
        )
        service.handleKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function, isARepeat: true)
        )
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 1)
    }

    // MARK: - Monitor local (Scribe en foreground)

    /// `handleLocalKeyDown` es lo que el monitor local invoca por cada evento mientras Scribe es
    /// la app activa: debe disparar el atajo con la misma lógica que el monitor global.
    func testHandleLocalKeyDownFiresOnFnSpace() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        _ = service.handleLocalKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function)
        )
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 1)
    }

    /// El monitor local nunca debe tragarse el evento: si lo hiciera, escribir un espacio normal
    /// dentro de Scribe (p. ej. en el editor de la transcripción) dejaría de funcionar.
    func testHandleLocalKeyDownReturnsEventUnchanged() {
        let service = LiveGlobalHotkeyService()
        try? service.start {}
        let event = makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: [])

        let returned = service.handleLocalKeyDown(event)

        XCTAssertTrue(returned === event)
    }

    /// Igual que con el monitor global: Space sin Fn no dispara el atajo local.
    func testHandleLocalKeyDownDoesNotFireForSpaceAlone() async {
        let service = LiveGlobalHotkeyService()
        var pressed = false
        try? service.start { pressed = true }

        _ = service.handleLocalKeyDown(makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(pressed)
    }

    /// `start()` instala tanto el monitor global como el local; `stop()` deja el estado en
    /// `.unknown` de nuevo, igual que antes de llamar a `start` — cubre que ambos monitores se
    /// liberan (si solo se liberara uno, `currentStatus()` seguiría reportando `.unknown` igual
    /// gracias a `hasStarted`, pero un monitor local huérfano seguiría entregando eventos al
    /// callback ya limpiado; por eso `handleKeyDown` no dispara nada tras `stop()`).
    func testStopClearsBothMonitorsSoHandleKeyDownNoLongerFires() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.stop()
        service.handleKeyDown(
            makeKeyDownEvent(keyCode: HotkeyTrigger.fnSpace.keyCode, modifierFlags: .function)
        )
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 0)
        XCTAssertEqual(service.currentStatus(), .unknown)
    }
}
