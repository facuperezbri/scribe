import AppKit
import Foundation

/// Estado del modelo de WhisperKit en disco.
enum ModelState: Equatable {
    case missing
    case downloading(progress: Double)
    case installed
}

/// Fase de la sesión de dictado en curso. Reemplaza los flags booleanos ad hoc
/// (`isStartingRecording`, `isTranscriptionCancelled`) que antes representaban estas
/// transiciones de forma implícita: cada paso del flujo grabar → transcribir es ahora un
/// caso explícito, y `handlePrimaryDictationAction` decide qué hacer solo mirando el caso
/// actual, sin estado oculto adicional.
enum DictationSessionState: Equatable {
    case idle
    case requestingPermission
    case startingRecording
    case recording
    case stoppingRecording
    case transcribing
}

/// Resultado del intento de transcripción más reciente, para que el overlay
/// flotante sepa si el paso a `.idle` que sigue a `.transcribing` fue un éxito (mostrar "Listo"
/// brevemente) o un fracaso/cancelación (ocultarse sin más, sin mostrar nada erróneo como si
/// hubiera terminado bien). `state.error` no alcanza por sí solo: distingue "hay un error" de
/// "no hay error", pero no distingue "recién terminó bien" de "está en reposo desde antes" (por
/// ejemplo, al abrir la app con una transcripción restaurada). Se limpia al arrancar la próxima
/// grabación (`startRecordingIfPossible()`), para que el overlay no reabra un "Listo" viejo.
enum TranscriptionOutcome: Equatable {
    case success
    case failure
    case cancelled
}

/// Fase de la burbuja flotante no intrusiva. Deliberadamente más angosta que
/// `PrimaryState`: la burbuja no existe para reflejar todo el estado de la app (eso ya lo hace la
/// ventana principal y el ítem de la barra de menús), solo para acompañar sin robar foco mientras
/// se graba/transcribe, y confirmar brevemente que terminó bien.
enum RecordingOverlayPhase: Equatable {
    case hidden
    case recording
    case transcribing
    case done
}

/// Estado completo de la app, separado en dimensiones independientes (permiso de micrófono,
/// modelo, sesión de dictado, error) en vez de un único enum plano que mezclaba las cuatro
/// cosas en un solo caso por vez.
struct AppState: Equatable {
    var permission: MicrophonePermissionStatus
    var model: ModelState
    var session: DictationSessionState
    var error: AppError?
}

/// Categoría visual de un `AppState`, para que la vista elija color sin conocer los casos puntuales.
enum StatusKind: Equatable {
    case neutral
    case active
    case warning
    case error
}

/// Acción destructiva que espera confirmación explícita del usuario antes de ejecutarse. Grabar
/// de nuevo sobre una transcripción existente ya no pasa por acá: en vez de bloquear con un
/// diálogo, `DictationViewModel` guarda esa transcripción en `previousTranscript` y arranca a
/// grabar directo, así que solo queda `.clearTranscript`.
enum PendingConfirmation: Equatable {
    case clearTranscript
}

/// Origen de una acción de grabar/detener: la ventana principal (`.userInterface`), el atajo
/// global de teclado (`.globalHotkey`) o el ítem "Iniciar dictado"/"Detener dictado" de la barra
/// de menús (`.menuBar`). Los tres invocan exactamente `handlePrimaryDictationAction`
/// en vez de duplicar la lógica de grabar/detener/transcribir.
enum DictationActionSource: Equatable {
    case userInterface
    case globalHotkey
    case menuBar
}

/// Estado "grande" que ve el usuario en el área central de la ventana compacta,
/// derivado de `AppState` + transcripción + estado del atajo global. Existe separado de
/// `statusText` (que sigue siendo el detalle chico, ad hoc por transición) porque necesita
/// un texto fijo y predecible por caso para el título grande, sin importar en qué paso
/// intermedio de una transición async se generó.
enum PrimaryState: Equatable {
    case ready
    case startingRecording
    case requestingPermission
    case recording
    case stoppingRecording
    case transcribing
    case transcriptReady
    case microphoneDenied
    case missingModel
    case downloadingModel
    case accessibilityRequired
    case error(String)
}

@MainActor
final class DictationViewModel: ObservableObject {
    @Published var state: AppState
    @Published var statusText: String
    @Published var transcript: String = "" {
        didSet { persistTranscript() }
    }
    @Published var showCopiedFeedback = false
    @Published var pendingConfirmation: PendingConfirmation?
    /// Transcripción que existía justo antes de que una nueva grabación la reemplazara,
    /// para poder recuperarla con `restorePreviousTranscript()`. Es
    /// un único búfer en memoria, no un historial: se pisa con cada reemplazo nuevo y se vacía al
    /// usarse, para dar una red de seguridad liviana sin construir un producto de historial.
    @Published private(set) var previousTranscript: String?
    @Published var recordingElapsed: TimeInterval = 0
    @Published var inputLevel: Float = 0
    @Published var hotkeyStatus: HotkeyStatus = .unknown
    @Published private(set) var lastTranscriptionOutcome: TranscriptionOutcome?

    private let audioRecorder: AudioRecordingServicing
    private let transcriptionService: TranscriptionServicing
    private let modelManager: ModelManaging
    private let clipboardService: ClipboardServicing
    private let globalHotkeyService: GlobalHotkeyServicing
    private let windowActivationService: WindowActivationServicing
    private let permissionStatusController: PermissionStatusController
    private let transcriptSessionController: TranscriptSessionController
    private let recordingMeter: RecordingMeter
    private let transcriptionAttemptCoordinator: TranscriptionAttemptCoordinator
    private(set) var lastRecordingURL: URL?
    private var transcriptionTask: Task<Void, Never>?

    init(
        audioRecorder: AudioRecordingServicing = AudioRecorderService(),
        modelManager: ModelManaging = ModelManager(),
        microphonePermissionManager: MicrophonePermissionManaging = MicrophonePermissionManager(),
        clipboardService: ClipboardServicing = ClipboardService(),
        transcriptStore: TranscriptStoring = FileTranscriptStore(),
        globalHotkeyService: GlobalHotkeyServicing = LiveGlobalHotkeyService(),
        windowActivationService: WindowActivationServicing = LiveWindowActivationService(),
        transcriptionService: TranscriptionServicing? = nil
    ) {
        self.audioRecorder = audioRecorder
        self.modelManager = modelManager
        self.clipboardService = clipboardService
        self.globalHotkeyService = globalHotkeyService
        self.windowActivationService = windowActivationService
        self.transcriptionService = transcriptionService ?? TranscriptionService(modelManager: modelManager)
        self.permissionStatusController = PermissionStatusController(microphonePermissionManager: microphonePermissionManager)
        self.transcriptSessionController = TranscriptSessionController(transcriptStore: transcriptStore)
        self.recordingMeter = RecordingMeter(audioRecorder: audioRecorder)
        self.transcriptionAttemptCoordinator = TranscriptionAttemptCoordinator(transcriptionService: self.transcriptionService)

        state = AppState(permission: .notDetermined, model: .missing, session: .idle, error: nil)
        statusText = "Listo"

        if let saved = transcriptSessionController.loadSavedTranscript(), !saved.isEmpty {
            transcript = saved
        }
        state = steadyState()
        statusText = statusText(for: state)

        self.audioRecorder.setInterruptionHandler { [weak self] error in
            Task { @MainActor in
                self?.handleRecordingInterruption(error)
            }
        }

        // Conecta el atajo global (Fn + Espacio) al mismo punto de entrada que usa el botón de la
        // UI, sin duplicar lógica de grabar/detener. `try?` porque el registro puede fallar sin
        // permiso de Accesibilidad (ver `LiveGlobalHotkeyService`); eso no debe impedir que el
        // resto de la app arranque, y el monitor queda instalado igual para cuando el permiso se
        // otorgue. No se llama a `windowActivationService.activateMainWindow()` acá — el atajo es
        // "background-first": grabar/detener no debe robarle el foco a la app en la que está el
        // usuario. Traer la ventana al frente queda reservado para una acción explícita del
        // usuario (p. ej. "Mostrar Scribe" del menú de la barra de menús), no para cada presión
        // del atajo. Ver `docs/DECISIONS.md`.
        try? self.globalHotkeyService.start { [weak self] in
            self?.handlePrimaryDictationAction(source: .globalHotkey)
        }
        hotkeyStatus = self.globalHotkeyService.currentStatus()
    }

    /// Estado "en reposo" real a partir del modelo instalado y el permiso de micrófono
    /// vigente, con `session` siempre en `.idle`. Única fuente de verdad para volver a un
    /// estado neutral (al iniciar la app, limpiar o cancelar una transcripción).
    private func steadyState() -> AppState {
        let permission = permissionStatusController.currentStatus
        guard modelManager.isModelInstalled else {
            return AppState(permission: permission, model: .missing, session: .idle, error: nil)
        }
        if permission == .restricted {
            return AppState(permission: permission, model: .installed, session: .idle, error: PermissionStatusController.restrictedMicrophoneError)
        }
        return AppState(permission: permission, model: .installed, session: .idle, error: nil)
    }

    private func statusText(for state: AppState) -> String {
        if let error = state.error {
            return error.message
        }
        if state.model == .missing {
            return "Modelo no instalado. Podés grabar, pero necesitás descargarlo para transcribir."
        }
        if state.permission == .denied {
            return "Micrófono bloqueado. Habilitalo en Ajustes del Sistema para poder grabar."
        }
        if !transcript.isEmpty {
            return "Transcripción restaurada. Listo para grabar de nuevo."
        }
        return "Listo"
    }

    private func persistTranscript() {
        transcriptSessionController.scheduleSave(transcript)
    }

    var recordButtonTitle: String {
        switch state.session {
        case .recording:
            return "Detener"
        case .stoppingRecording:
            return "Deteniendo..."
        default:
            return "Grabar"
        }
    }

    var isModelInstalled: Bool {
        modelManager.isModelInstalled
    }

    var downloadProgress: Double {
        if case .downloading(let progress) = state.model {
            return progress
        }
        return 0
    }

    var isRecording: Bool { state.session == .recording }
    var isTranscribing: Bool { state.session == .transcribing }
    var isMicrophonePermissionDenied: Bool { state.permission == .denied }
    var isDownloadingModel: Bool {
        if case .downloading = state.model { return true }
        return false
    }

    var isError: Bool {
        state.error != nil || state.permission == .denied
    }

    var statusKind: StatusKind {
        if isError { return .error }
        switch state.session {
        case .recording, .stoppingRecording, .transcribing, .requestingPermission, .startingRecording:
            return .active
        case .idle:
            break
        }
        if isDownloadingModel { return .active }
        if state.model == .missing { return .warning }
        return .neutral
    }

    var isBusy: Bool {
        if isDownloadingModel { return true }
        switch state.session {
        case .transcribing, .requestingPermission, .stoppingRecording:
            return true
        default:
            return false
        }
    }

    /// `nil` si la grabación todavía no es larga, o el aviso correspondiente al umbral
    /// alcanzado. Solo tiene sentido mientras se está grabando.
    var recordingWarningText: String? {
        guard state.session == .recording else { return nil }
        switch RecordingDurationPolicy.warning(forElapsed: recordingElapsed) {
        case .strong:
            return "Grabación muy larga: se recomienda detener y transcribir ahora."
        case .soft:
            return "Grabación larga: la transcripción puede tardar más."
        case .none:
            return nil
        }
    }

    var isStrongRecordingWarning: Bool {
        state.session == .recording && RecordingDurationPolicy.warning(forElapsed: recordingElapsed) == .strong
    }

    /// Resuelve el `PrimaryState` para el área central de la ventana compacta. El
    /// orden importa: una sesión en curso (grabando/transcribiendo/etc.) manda siempre, porque
    /// es la verdad más urgente y en vivo, incluso si en paralelo falta el modelo o el permiso
    /// de Accesibilidad no está otorgado (ninguno de los dos bloquea grabar). Recién en reposo
    /// (`.idle`) se evalúan esos bloqueos, en el mismo orden de prioridad que ya usa
    /// `statusText(for:)`, y por último si hay accesibilidad pendiente o una transcripción para
    /// mostrar.
    var primaryState: PrimaryState {
        if let error = state.error {
            return .error(error.message)
        }
        switch state.session {
        case .recording: return .recording
        case .stoppingRecording: return .stoppingRecording
        case .transcribing: return .transcribing
        case .startingRecording: return .startingRecording
        case .requestingPermission: return .requestingPermission
        case .idle: break
        }
        if state.permission == .denied { return .microphoneDenied }
        if state.model == .missing { return .missingModel }
        if isDownloadingModel { return .downloadingModel }
        if hotkeyStatus == .accessibilityPermissionRequired { return .accessibilityRequired }
        if !transcript.isEmpty { return .transcriptReady }
        return .ready
    }

    /// Fase de la burbuja flotante: a diferencia de `primaryState`, no le
    /// importan permiso/modelo/Accesibilidad ni la transcripción en sí — solo grabar/transcribir
    /// y el instante posterior al éxito (`.done`, breve, para mostrar "Listo" y desaparecer).
    /// `lastTranscriptionOutcome` es lo que distingue ese instante de un reposo cualquiera (por
    /// ejemplo, al abrir la app con una transcripción restaurada, donde no corresponde mostrar
    /// nada): se limpia al arrancar la próxima grabación, así que `.done` no reaparece solo.
    var overlayPhase: RecordingOverlayPhase {
        switch state.session {
        case .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .idle, .requestingPermission, .startingRecording, .stoppingRecording:
            return lastTranscriptionOutcome == .success ? .done : .hidden
        }
    }

    var primaryStateTitle: String {
        switch primaryState {
        case .ready: return "Listo para dictar"
        case .startingRecording: return "Preparando grabación..."
        case .requestingPermission: return "Solicitando permiso de micrófono..."
        case .recording: return "Grabando..."
        case .stoppingRecording: return "Deteniendo..."
        case .transcribing: return "Transcribiendo localmente..."
        case .transcriptReady: return "Transcripción lista"
        case .microphoneDenied: return "Permiso de micrófono requerido"
        case .missingModel: return "Modelo requerido"
        case .downloadingModel: return "Descargando modelo..."
        case .accessibilityRequired: return "Permiso de Accesibilidad requerido"
        case .error(let message): return message
        }
    }

    /// Pista chica bajo el título grande, solo para el estado neutral de reposo: en el resto de
    /// los casos ya hay suficiente detalle (feedback de grabación, spinner de transcripción,
    /// botón de copiar) como para no necesitar una segunda línea de texto.
    var primaryStateHint: String? {
        primaryState == .ready ? "Presioná Fn + Espacio para dictar" : nil
    }

    /// Si corresponde destacar "Copiar" como acción principal del área central, en vez de un
    /// texto de estado sin acción asociada.
    var showCopyCallToAction: Bool {
        primaryState == .transcriptReady
    }

    /// Punto único de entrada para una acción de grabar/detener, sin importar de dónde venga:
    /// el botón de la UI, el atajo de teclado global (pasando `source: .globalHotkey`) o el ítem
    /// de la barra de menús. Todos los orígenes comparten exactamente esta lógica, sin duplicar
    /// el flujo de negocio.
    ///
    /// La seguridad ante toques repetidos no depende de un flag aparte: `startRecordingIfPossible()`
    /// deja `state.session` en `.startingRecording` de forma sincrónica antes de lanzar el
    /// `Task`, así que una segunda invocación mientras arranca ve un `session` distinto de
    /// `.idle` y cae en el `default` sin efecto.
    func handlePrimaryDictationAction(source: DictationActionSource = .userInterface) {
        guard !isBusy, pendingConfirmation == nil else { return }
        switch state.session {
        case .recording:
            stopRecording()
        case .idle:
            // Grabar de nuevo con una transcripción existente ya no pide confirmación: arranca
            // directo y la transcripción reemplazada queda en `previousTranscript` (ver
            // `transcribe(url:)`), recuperable con `restorePreviousTranscript()`.
            startRecordingIfPossible()
        default:
            break
        }
    }

    /// Confirma o cancela la acción destructiva pendiente (hoy, solo limpiar transcripción).
    func confirmPendingAction() {
        switch pendingConfirmation {
        case .clearTranscript:
            pendingConfirmation = nil
            performClear()
        case nil:
            break
        }
    }

    func cancelPendingConfirmation() {
        pendingConfirmation = nil
    }

    private func startRecordingIfPossible() {
        state.session = .startingRecording
        lastTranscriptionOutcome = nil
        Task {
            await startRecordingFlow()
        }
    }

    private func startRecordingFlow() async {
        switch permissionStatusController.currentStatus {
        case .authorized:
            beginRecording()

        case .notDetermined:
            state.session = .requestingPermission
            statusText = "Solicitando permiso de micrófono..."
            let granted = await permissionStatusController.requestAccess()
            if granted {
                beginRecording()
            } else {
                state.permission = .denied
                state.session = .idle
                statusText = "Permiso de micrófono denegado. Habilitalo en Ajustes del Sistema para poder grabar."
            }

        case .denied:
            state.permission = .denied
            state.session = .idle
            statusText = "Micrófono bloqueado. Habilitalo en Ajustes del Sistema para poder grabar."

        case .restricted:
            state.permission = .restricted
            state.session = .idle
            state.error = PermissionStatusController.restrictedMicrophoneError
        }
    }

    /// Abre la sección de privacidad de Micrófono en Ajustes del Sistema.
    func openMicrophonePrivacySettings() {
        permissionStatusController.openMicrophonePrivacySettings()
    }

    /// Abre la sección de privacidad de Accesibilidad en Ajustes del Sistema (donde se habilita
    /// Scribe para que el atajo global de Fn + Espacio funcione). Si el deep link no resuelve en esta
    /// versión de macOS, `NSWorkspace` simplemente no abre nada; no hay fallback porque no vale
    /// la pena mantener dos textos de ayuda ligeramente distintos para ese caso borde.
    func openAccessibilityPrivacySettings() {
        permissionStatusController.openAccessibilityPrivacySettings()
    }

    /// Vuelve a consultar el estado del atajo global sin reiniciar el servicio. Se llama al
    /// volver a la app desde Ajustes del Sistema y también puede ofrecerse como
    /// botón explícito ("Revisar permiso") para el mismo efecto.
    func refreshHotkeyStatus() {
        hotkeyStatus = globalHotkeyService.currentStatus()
    }

    /// Conecta la acción `openWindow` de SwiftUI con `WindowActivationServicing`, para el caso en
    /// que el atajo global se presiona después de que el usuario cerró la ventana principal del
    /// todo. `ContentView` llama esto una sola vez al aparecer, porque un servicio plano fuera de
    /// la jerarquía de vistas no tiene `@Environment` propio.
    func registerWindowReopenHandler(_ handler: @escaping () -> Void) {
        windowActivationService.registerReopenHandler(handler)
    }

    /// Trae la ventana principal al frente de forma explícita: el atajo global no lo hace por su
    /// cuenta (ver `docs/DECISIONS.md`), así que esta es la única vía prevista para mostrarla
    /// bajo demanda — hoy la usa "Mostrar Scribe" del menú de la barra de menús.
    func showMainWindow() {
        windowActivationService.activateMainWindow()
    }

    private func beginRecording() {
        do {
            let fileURL = try audioRecorder.startRecording()
            lastRecordingURL = fileURL
            state.session = .recording
            state.error = nil
            statusText = "Grabando..."
            startMetering()
        } catch {
            let appError = AppError(category: .recording, underlying: error)
            state.session = .idle
            state.error = appError
            statusText = appError.message
        }
    }

    private func stopRecording() {
        // Estado transitorio fijado de forma sincrónica: bloquea un segundo tap antes de
        // que audioRecorder.stopRecording() termine, evitando una doble detención/transcripción.
        stopMetering()
        state.session = .stoppingRecording
        statusText = "Deteniendo grabación..."

        guard let url = audioRecorder.stopRecording() else {
            let appError = AppError(category: .recording, message: "No se encontró el audio grabado.")
            state.session = .idle
            state.error = appError
            statusText = appError.message
            return
        }
        lastRecordingURL = url
        state.error = nil

        guard modelManager.isModelInstalled else {
            state.model = .missing
            state.session = .idle
            statusText = "Modelo no instalado. Descargalo para transcribir tu grabación."
            return
        }

        transcriptionTask = Task { await transcribe(url: url) }
    }

    /// Cancela la transcripción en curso. `transcriptionTask?.cancel()` es solo una señal
    /// cooperativa; `transcriptionAttemptCoordinator.cancel()` es lo que realmente evita que un
    /// resultado que llega tarde sobrescriba el estado ya revertido.
    func cancelTranscription() {
        guard state.session == .transcribing else { return }
        transcriptionAttemptCoordinator.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        state = steadyState()
        statusText = "Transcripción cancelada."
        lastTranscriptionOutcome = .cancelled
    }

    private func startMetering() {
        recordingElapsed = 0
        inputLevel = 0
        recordingMeter.start { [weak self] elapsed, level in
            self?.recordingElapsed = elapsed
            self?.inputLevel = level
        }
    }

    private func stopMetering() {
        recordingMeter.stop()
        inputLevel = 0
    }

    /// Se dispara cuando `audioRecorder` reporta que la grabación terminó por sí sola (otra
    /// app tomó el dispositivo de audio, o un error de codificación) sin que el usuario la
    /// haya detenido. Solo tiene efecto si todavía estábamos en `.recording`: si el usuario ya
    /// detuvo la grabación por su cuenta, este callback puede llegar tarde y no debe pisar el
    /// estado que ya se actualizó.
    private func handleRecordingInterruption(_ error: Error?) {
        guard state.session == .recording else { return }
        stopMetering()
        let appError = AppError(
            category: .recording,
            message: "La grabación se interrumpió. Probá grabar de nuevo.",
            underlying: error
        )
        state.session = .idle
        state.error = appError
        statusText = appError.message
    }

    private func transcribe(url: URL) async {
        state.session = .transcribing
        statusText = "Transcribiendo..."
        switch await transcriptionAttemptCoordinator.transcribe(url: url) {
        case .cancelled:
            // Llegó tarde: `cancelTranscription()` ya revirtió el estado y limpió
            // `transcriptionTask`, así que no hay nada más que hacer con este resultado.
            return

        case .success(let text):
            // TODO(modo append): hoy cada transcripción reemplaza la anterior; en algún momento
            // se podría agregar un modo que concatene en vez de sobrescribir. Justo antes de
            // perderla, se guarda como red de seguridad: no hay confirmación bloqueante antes de
            // este punto, así que esta es la única chance de recuperar el texto anterior.
            if !transcript.isEmpty {
                previousTranscript = transcript
            }
            transcript = text
            state.session = .idle
            state.error = nil
            statusText = "Transcripción lista."
            // El audio ya cumplió su propósito: se borra para no dejar WAVs temporales
            // acumulándose en disco más allá de lo necesario.
            audioRecorder.deleteCurrentFile()
            lastRecordingURL = nil
            lastTranscriptionOutcome = .success

        case .failure(let appError):
            state.session = .idle
            state.error = appError
            statusText = appError.message
            lastTranscriptionOutcome = .failure
        }
        transcriptionTask = nil
    }

    /// Descarga del modelo iniciada explícitamente por el usuario (botón "Descargar modelo").
    /// Este es el único lugar de la app donde se dispara una descarga de red.
    func downloadModel() {
        guard !isBusy else { return }
        state.model = .downloading(progress: 0)
        statusText = "Descargando modelo... 0%"
        Task {
            do {
                _ = try await modelManager.downloadModel { [weak self] fraction in
                    Task { @MainActor in
                        self?.state.model = .downloading(progress: fraction)
                        self?.statusText = "Descargando modelo... \(Int(fraction * 100))%"
                    }
                }
                transcriptionService.invalidate()
                state.model = .installed
                state.error = nil
                if let url = lastRecordingURL {
                    await transcribe(url: url)
                } else {
                    state.session = .idle
                    statusText = "Modelo instalado. Listo."
                }
            } catch {
                let appError = AppError(category: .model, underlying: error)
                state.model = .missing
                statusText = appError.message
            }
        }
    }

    func revealModelInFinder() {
        modelManager.revealInFinder()
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        clipboardService.copy(transcript)
        showCopiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCopiedFeedback = false
        }
    }

    /// No permite limpiar mientras hay una transcripción en curso: el texto que se vería
    /// borrado es el de la grabación anterior, no el que se está calculando, y limpiarlo
    /// en ese momento sería confuso. Si hay texto, se pide confirmación antes de borrarlo.
    func clearTranscript() {
        guard !isBusy, pendingConfirmation == nil else { return }
        guard !transcript.isEmpty else {
            performClear()
            return
        }
        pendingConfirmation = .clearTranscript
    }

    /// Recupera la transcripción guardada en `previousTranscript` (la que había justo antes del
    /// último reemplazo) y vacía el búfer: es una recuperación de un solo uso, no un historial.
    func restorePreviousTranscript() {
        guard let previousTranscript else { return }
        transcript = previousTranscript
        self.previousTranscript = nil
    }

    /// Vacía la transcripción y recalcula el estado real (no asume `.idle` sin más): si falta
    /// el modelo o el micrófono está bloqueado, el estado debe seguir reflejando eso. También
    /// vacía `previousTranscript`: limpiar ya tiene su propia confirmación explícita, así que no
    /// hace falta que la red de seguridad de "reemplazo" siga ofreciendo un texto de un reemplazo
    /// previo después de un borrado intencional y ya confirmado.
    private func performClear() {
        transcript = ""
        previousTranscript = nil
        state = steadyState()
        statusText = statusText(for: state)
    }
}
