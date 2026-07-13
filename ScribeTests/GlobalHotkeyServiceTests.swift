import AppKit
import XCTest
@testable import Scribe

/// Cubre el contrato de `GlobalHotkeyServicing` a través del fake (sin depender de un evento de
/// teclado real) y que `DictationViewModel` conecta el callback del atajo global con
/// `handlePrimaryDictationAction(source: .globalHotkey)` sin duplicar el flujo de grabar/detener.
///
/// Los casos que ejercitan `DictationViewModel` completo (mantener Fn presionada, push-to-talk)
/// simulan cada flanco del atajo a través de `FakeGlobalHotkeyService.simulateHotkeyPressed()`
/// (una llamada por flanco: la primera equivale a presionar Fn, la segunda a soltarla),
/// nunca con un evento real de teclado — eso es justamente lo que `LiveGlobalHotkeyService`
/// traduce a esa llamada, y queda fuera del alcance de un test unitario. La lógica real de
/// detección de flancos de `.function` y la máquina de estados de manos libres (doble toque para
/// bloquear) de `LiveGlobalHotkeyService.handleFlagsChanged`/`PushToTalkState` sí se cubren más
/// abajo con eventos sintéticos, sin instalar ningún `CGEventTap` real.
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

    /// Push-to-talk: el segundo flanco del atajo (soltar Fn), con la grabación en curso,
    /// detiene y arranca la transcripción — el mismo flujo que produce un segundo toque del botón
    /// de la UI.
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

    // MARK: - Estado del atajo y permiso de Monitoreo de entrada

    func testHotkeyStatusReflectsActiveAfterInit() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = .active
        let viewModel = makeViewModel(hotkeyService: hotkeyService)

        XCTAssertEqual(viewModel.hotkeyStatus, .active)
    }

    /// El registro sigue intentando crear el tap y solo falta el permiso de Monitoreo de
    /// entrada; eso no debe impedir que la app arranque ni tumbar `init`.
    func testHotkeyStatusReflectsInputMonitoringPermissionRequiredAfterInit() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.inputMonitoringPermissionDenied)
        hotkeyService.statusResult = .inputMonitoringPermissionRequired
        let viewModel = makeViewModel(hotkeyService: hotkeyService)

        XCTAssertEqual(viewModel.hotkeyStatus, .inputMonitoringPermissionRequired)
    }

    /// Una falla de registro no relacionada con el permiso tampoco es fatal: el botón de la UI
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

    /// Simula que el usuario otorgó el permiso de Monitoreo de entrada después de que la app
    /// arrancó: `refreshHotkeyStatus()` debe reflejarlo sin reiniciar el servicio.
    func testRefreshHotkeyStatusUpdatesAfterPermissionGrantedLater() {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.startResult = .failure(GlobalHotkeyServiceError.inputMonitoringPermissionDenied)
        hotkeyService.statusResult = .inputMonitoringPermissionRequired
        let viewModel = makeViewModel(hotkeyService: hotkeyService)
        XCTAssertEqual(viewModel.hotkeyStatus, .inputMonitoringPermissionRequired)

        hotkeyService.statusResult = .active
        viewModel.refreshHotkeyStatus()

        XCTAssertEqual(viewModel.hotkeyStatus, .active)
    }

    /// El fake sigue disparando el flujo centralizado sin importar el estado reportado por
    /// `currentStatus()` — esa distinción es solo para la UI, no cambia el cableado del atajo.
    func testGlobalHotkeyStillUsesCentralizedWorkflowWhenInputMonitoringPermissionIsRequired() async {
        let hotkeyService = FakeGlobalHotkeyService()
        hotkeyService.statusResult = .inputMonitoringPermissionRequired
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(hotkeyService: hotkeyService, audioRecorder: audioRecorder)

        hotkeyService.simulateHotkeyPressed()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(audioRecorder.startRecordingCallCount, 1)
        XCTAssertEqual(viewModel.state.session, .recording)
    }

    /// `LiveGlobalHotkeyService.currentStatus()` antes de `start` no depende del permiso de
    /// Monitoreo de entrada: no hay callback ni tap instalado todavía, así que siempre es
    /// `.unknown`.
    func testLiveServiceStatusIsUnknownBeforeStart() {
        let service = LiveGlobalHotkeyService()
        XCTAssertEqual(service.currentStatus(), .unknown)
    }

    /// Después de `start`, el estado real depende del permiso de Monitoreo de entrada de esta
    /// máquina (no controlable en CI, y `CGEvent.tapCreate` directamente no crea el tap si falta),
    /// así que solo se verifica que deje de ser `.unknown`/`.failed` — sin asumir si el proceso
    /// está o no habilitado.
    func testLiveServiceStatusIsActiveOrPermissionRequiredAfterStart() {
        let service = LiveGlobalHotkeyService()
        try? service.start {}

        switch service.currentStatus() {
        case .active, .inputMonitoringPermissionRequired:
            break
        case .unknown, .failed:
            XCTFail("Se esperaba .active o .inputMonitoringPermissionRequired después de start, se obtuvo \(service.currentStatus())")
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
    // `NSEvent.keyEvent`, sin depender de un teclado real ni de un `CGEventTap` real entregando
    // eventos del sistema. Las transiciones diferidas (el detenimiento tras soltar, ver "Modo
    // manos libres" más abajo) disparan el callback con `Task { @MainActor in ... }`, así que
    // cada aserción positiva espera brevemente antes de verificar.

    private func makeFlagsChangedEvent(modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 63 // kVK_Function; irrelevant para la lógica, que solo mira modifierFlags.
        )!
    }

    // MARK: - HotkeyModifierTrigger (modificador configurable, fallback si Fn no fuera viable)

    func testFunctionTriggerIsActiveWhenFunctionFlagPresent() {
        XCTAssertTrue(HotkeyModifierTrigger.function.isActive(in: .function))
    }

    func testFunctionTriggerIsNotActiveWithoutFunctionFlag() {
        XCTAssertFalse(HotkeyModifierTrigger.function.isActive(in: .option))
    }

    func testControlTriggerIsActiveWhenControlFlagPresent() {
        XCTAssertTrue(HotkeyModifierTrigger.control.isActive(in: .control))
    }

    func testControlTriggerIsNotActiveWithoutControlFlag() {
        XCTAssertFalse(HotkeyModifierTrigger.control.isActive(in: .option))
    }

    /// Documenta el compromiso conocido (ver DECISIONS.md): Control sigue disparando el atajo aun
    /// combinado con otros modificadores, como en Ctrl+Shift+algo. `HotkeyModifierTrigger.control`
    /// ya no es el default, pero sigue siendo un fallback válido (ver
    /// `HotkeyModifierTrigger` en `GlobalHotkeyService.swift`).
    func testControlTriggerIsActiveEvenCombinedWithOtherModifiers() {
        XCTAssertTrue(HotkeyModifierTrigger.control.isActive(in: [.control, .shift]))
    }

    /// `LiveGlobalHotkeyService` no tiene Fn hardcodeada en su lógica de detección:
    /// instanciarlo con otro `HotkeyModifierTrigger` (por ejemplo, un fallback para un teclado o
    /// flujo de trabajo donde la validación confirme que Fn no es viable) alcanza para
    /// cambiar qué modificador dispara el atajo, sin tocar `handleFlagsChanged` ni el modelo de
    /// permisos.
    func testCustomTriggerIsHonoredInsteadOfTheDefault() async {
        let fallback = HotkeyModifierTrigger(modifierFlag: .option)
        let service = LiveGlobalHotkeyService(trigger: fallback)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        // El modificador por defecto (Fn) ya no dispara nada con este trigger inyectado.
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(pressCount, 0)

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .option))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(pressCount, 1)
    }

    // MARK: - Detección real de Fn (LiveGlobalHotkeyService.handleFlagsChanged)

    func testHandleFlagsChangedFiresWhenFunctionGoesDown() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 1)
    }

    /// El mismo callback dispara de nuevo cuando Fn se suelta — lo que convierte al atajo en
    /// push-to-talk — pero ya no en el instante exacto de soltar: espera `doubleTapWindow` por si
    /// llega un segundo toque (ver "Modo manos libres" más abajo) antes de asumir que fue un
    /// mantener-presionado normal. Usa un `doubleTapWindow` corto inyectado en vez del real
    /// (`NSEvent.doubleClickInterval`, unos cientos de milisegundos) para no depender de esperas
    /// largas en el test.
    func testHandleFlagsChangedFiresAgainWhenFunctionGoesUpAfterDoubleTapWindowElapses() async {
        let service = LiveGlobalHotkeyService(doubleTapWindow: 0.02)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(10))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(pressCount, 2)
    }

    /// Otro modificador (Shift) cambiando mientras Fn sigue presionada no debe disparar el
    /// atajo de nuevo: solo importa el flanco de Fn, no cualquier cambio en `modifierFlags`. No
    /// hay flanco de soltada acá, así que `doubleTapWindow` no entra en juego.
    func testHandleFlagsChangedDoesNotFireAgainWhileFunctionStaysDownAndAnotherModifierChanges() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(50))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: [.function, .shift]))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 1)
    }

    /// Option sola (sin Fn) no debe disparar el atajo por defecto.
    func testHandleFlagsChangedDoesNotFireForOptionAlone() async {
        let service = LiveGlobalHotkeyService()
        var pressed = false
        try? service.start { pressed = true }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .option))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(pressed)
    }

    /// Regression guard: Control ya no es el modificador por defecto, así que sostenerlo solo no
    /// debe disparar el atajo (a diferencia de la migración anterior a esta).
    func testHandleFlagsChangedDoesNotFireForControlAlone() async {
        let service = LiveGlobalHotkeyService()
        var pressed = false
        try? service.start { pressed = true }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .control))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(pressed)
    }

    // MARK: - stop() limpia el estado (ya no hay un segundo monitor local que verificar)

    /// A diferencia de la migración anterior (que instalaba un monitor global y uno local), este
    /// servicio ya no tiene un segundo mecanismo de entrega que verificar por separado: solo
    /// existe el `CGEventTap` y el estado interno que `handleFlagsChanged` consulta directamente.
    /// Este test cubre ese estado interno: después de `stop()`, un flanco posterior no debe
    /// disparar el callback ya limpiado, y `currentStatus()` vuelve a `.unknown`.
    func testStopClearsStateSoHandleFlagsChangedNoLongerFiresTheOldCallback() async {
        let service = LiveGlobalHotkeyService()
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(pressCount, 1)

        service.stop()
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(service.currentStatus(), .unknown)
    }

    /// `handleTapEvent` reactiva el tap cuando macOS lo deshabilita por timeout o intervención del
    /// usuario, y siempre deja pasar ese evento de control sin tocarlo — nunca lo consume, porque
    /// no representa un flanco de `trigger`.
    func testHandleTapEventPassesThroughControlEventsAfterReEnablingTheTap() {
        let service = LiveGlobalHotkeyService()
        let controlEvent = CGEvent(source: nil)!

        let resultAfterTimeout = service.handleTapEvent(type: .tapDisabledByTimeout, event: controlEvent)
        let resultAfterUserInput = service.handleTapEvent(type: .tapDisabledByUserInput, event: controlEvent)

        XCTAssertNotNil(resultAfterTimeout)
        XCTAssertNotNil(resultAfterUserInput)
    }

    // MARK: - Modo manos libres (doble toque para bloquear grabando)

    /// Un mantener-presionado normal (una sola presión y suelta, sin un segundo toque dentro de
    /// `doubleTapWindow`) sigue funcionando como push-to-talk de siempre: arranca al presionar,
    /// se detiene solo — mediante el `pendingStopTask` diferido de `handleTriggerUp` — una vez que
    /// vence la ventana sin un segundo toque.
    func testNormalPressAndReleaseStopsAfterDoubleTapWindowElapsesWithNoSecondPress() async {
        let service = LiveGlobalHotkeyService(doubleTapWindow: 0.03)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(service.pushToTalkState, .recording)

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(pressCount, 1, "no debe detener todavía: sigue dentro de doubleTapWindow")

        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(pressCount, 2)
        XCTAssertEqual(service.pushToTalkState, .idle)
    }

    /// El caso central del modo manos libres: presionar, soltar, y volver a presionar dentro de
    /// `doubleTapWindow` bloquea la grabación en curso en vez de iniciar una segunda — el
    /// callback no vuelve a dispararse (`DictationViewModel` ya sabe que está grabando desde el
    /// primer toque) — y soltar la segunda vez, ya bloqueado, tampoco la detiene.
    func testDoubleTapWithinWindowLocksRecordingWithoutStoppingOnRelease() async {
        let service = LiveGlobalHotkeyService(doubleTapWindow: 0.05)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function)) // 1er toque: abajo
        try? await Task.sleep(for: .milliseconds(5))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: [])) // 1er toque: arriba
        try? await Task.sleep(for: .milliseconds(5))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function)) // 2do toque, dentro de la ventana
        try? await Task.sleep(for: .milliseconds(5))

        XCTAssertEqual(pressCount, 1, "el doble toque no debe emitir un segundo callback: ya se está grabando")
        XCTAssertEqual(service.pushToTalkState, .locked)

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: [])) // 2do toque: arriba, ya bloqueado
        try? await Task.sleep(for: .milliseconds(80)) // más que doubleTapWindow

        XCTAssertEqual(pressCount, 1, "bloqueado: soltar no debe detener la grabación aunque pase el tiempo del doble toque")
        XCTAssertEqual(service.pushToTalkState, .locked)
    }

    /// Estando bloqueado, un toque simple posterior detiene la grabación en el flanco de bajada
    /// mismo (no hace falta soltar) y no queda ningún detenimiento diferido pendiente que dispare
    /// un tercer callback espurio cuando esa soltada llegue después.
    func testSingleTapWhileLockedStopsRecordingWithoutAStrayLaterCallback() async {
        let service = LiveGlobalHotkeyService(doubleTapWindow: 0.05)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(5))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(5))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(service.pushToTalkState, .locked)

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(pressCount, 2, "el toque simple debe detener de inmediato, en el flanco de bajada")
        XCTAssertEqual(service.pushToTalkState, .idle)

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(pressCount, 2, "la soltada del toque que detiene no debe disparar un tercer callback")
        XCTAssertEqual(service.pushToTalkState, .idle)
    }

    /// Guarda de regresión para el bug detectado durante el diseño: un segundo toque que llega
    /// *después* de que ya venció `doubleTapWindow` (y por lo tanto el detenimiento diferido ya
    /// disparó solo) no debe tratarse como parte de ningún doble toque — es una presión nueva e
    /// independiente, que arranca su propia grabación.
    func testSecondPressAfterWindowElapsedStartsANewIndependentRecording() async {
        let service = LiveGlobalHotkeyService(doubleTapWindow: 0.02)
        var pressCount = 0
        try? service.start { pressCount += 1 }

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(5))
        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: []))
        try? await Task.sleep(for: .milliseconds(60)) // deja vencer doubleTapWindow: se detiene solo

        XCTAssertEqual(pressCount, 2)
        XCTAssertEqual(service.pushToTalkState, .idle)

        service.handleFlagsChanged(makeFlagsChangedEvent(modifierFlags: .function))
        try? await Task.sleep(for: .milliseconds(5))

        XCTAssertEqual(pressCount, 3)
        XCTAssertEqual(service.pushToTalkState, .recording)
    }
}
