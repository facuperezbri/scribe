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

/// Acción destructiva que espera confirmación explícita del usuario antes de ejecutarse.
enum PendingConfirmation: Equatable {
    case replaceTranscript
    case clearTranscript
}

/// Origen de una acción de grabar/detener. Hoy solo existe `.userInterface`; `.globalHotkey`
/// queda reservado para cuando MVP3 agregue el atajo global, que deberá invocar
/// `handlePrimaryDictationAction(source: .globalHotkey)` en vez de duplicar esta lógica.
enum DictationActionSource: Equatable {
    case userInterface
    case globalHotkey
}

/// Estado "grande" que ve el usuario en el área central de la ventana compacta (Fase 8),
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
    @Published var recordingElapsed: TimeInterval = 0
    @Published var inputLevel: Float = 0
    @Published var hotkeyStatus: HotkeyStatus = .unknown

    private let audioRecorder: AudioRecordingServicing
    private let transcriptionService: TranscriptionServicing
    private let modelManager: ModelManaging
    private let microphonePermissionManager: MicrophonePermissionManaging
    private let clipboardService: ClipboardServicing
    private let transcriptStore: TranscriptStoring
    private let globalHotkeyService: GlobalHotkeyServicing
    private let windowActivationService: WindowActivationServicing
    private(set) var lastRecordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var pendingTranscriptSaveTask: Task<Void, Never>?
    /// Identifica el intento de transcripción en curso, para descartar un resultado que
    /// llega tarde (tras cancelar, o tras haber arrancado una grabación nueva) sin importar
    /// qué caso tenga `state.session` en ese momento: comparar contra este id es la única
    /// forma confiable de saber si un resultado async sigue siendo relevante.
    private var currentTranscriptionAttempt: UUID?

    private static let restrictedMicrophoneError = AppError(
        category: .microphonePermission,
        message: "El acceso al micrófono está restringido en este equipo (gestión parental o de la organización). No se puede habilitar desde la app."
    )
    private static let softWarningThreshold: TimeInterval = 120
    private static let strongWarningThreshold: TimeInterval = 300

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
        self.microphonePermissionManager = microphonePermissionManager
        self.clipboardService = clipboardService
        self.transcriptStore = transcriptStore
        self.globalHotkeyService = globalHotkeyService
        self.windowActivationService = windowActivationService
        self.transcriptionService = transcriptionService ?? TranscriptionService(modelManager: modelManager)

        state = AppState(permission: .notDetermined, model: .missing, session: .idle, error: nil)
        statusText = "Listo"

        if let saved = transcriptStore.loadTranscript(), !saved.isEmpty {
            transcript = saved
        }
        state = steadyState()
        statusText = statusText(for: state)

        self.audioRecorder.setInterruptionHandler { [weak self] error in
            Task { @MainActor in
                self?.handleRecordingInterruption(error)
            }
        }

        // Conecta el atajo global (Fn + Espacio, Fase 9 — antes Option solo en la Fase 5 de MVP3)
        // al mismo punto de entrada que usa el botón de la UI, sin duplicar lógica de grabar/
        // detener. `try?` porque el registro
        // puede fallar sin permiso de Accesibilidad (ver `LiveGlobalHotkeyService`); eso no debe
        // impedir que el resto de la app arranque, y el monitor queda instalado igual para cuando
        // el permiso se otorgue. Fase 3 de MVP4: ya no se llama a `windowActivationService.
        // activateMainWindow()` acá — el atajo pasó a ser "background-first" (como Wispr Flow):
        // grabar/detener no debe robarle el foco a la app en la que está el usuario. Traer la
        // ventana al frente queda reservado para una acción explícita del usuario (p. ej. "Mostrar
        // Scribe" del menú de la barra de menús, Fase 4), no para cada presión del atajo.
        try? self.globalHotkeyService.start { [weak self] in
            self?.handlePrimaryDictationAction(source: .globalHotkey)
        }
        hotkeyStatus = self.globalHotkeyService.currentStatus()
    }

    /// Estado "en reposo" real a partir del modelo instalado y el permiso de micrófono
    /// vigente, con `session` siempre en `.idle`. Única fuente de verdad para volver a un
    /// estado neutral (al iniciar la app, limpiar o cancelar una transcripción).
    private func steadyState() -> AppState {
        let permission = microphonePermissionManager.currentStatus()
        guard modelManager.isModelInstalled else {
            return AppState(permission: permission, model: .missing, session: .idle, error: nil)
        }
        if permission == .restricted {
            return AppState(permission: permission, model: .installed, session: .idle, error: Self.restrictedMicrophoneError)
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

    /// Guarda la transcripción con un pequeño debounce para no escribir a disco en cada
    /// tecla presionada en el editor.
    private func persistTranscript() {
        pendingTranscriptSaveTask?.cancel()
        let textToSave = transcript
        pendingTranscriptSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.transcriptStore.saveTranscript(textToSave)
        }
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
        if recordingElapsed >= Self.strongWarningThreshold {
            return "Grabación muy larga: se recomienda detener y transcribir ahora."
        }
        if recordingElapsed >= Self.softWarningThreshold {
            return "Grabación larga: la transcripción puede tardar más."
        }
        return nil
    }

    var isStrongRecordingWarning: Bool {
        state.session == .recording && recordingElapsed >= Self.strongWarningThreshold
    }

    /// Resuelve el `PrimaryState` para el área central de la ventana compacta (Fase 8). El
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
    /// hoy solo el botón de la UI, más adelante también el atajo de teclado global de MVP3
    /// (pasando `source: .globalHotkey`). Ambos orígenes comparten exactamente esta lógica,
    /// así que MVP3 no necesita duplicar el flujo de negocio, solo invocar esta función.
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
            if !transcript.isEmpty {
                pendingConfirmation = .replaceTranscript
            } else {
                startRecordingIfPossible()
            }
        default:
            break
        }
    }

    /// Confirma o cancela la acción destructiva pendiente (reemplazar o limpiar transcripción).
    func confirmPendingAction() {
        switch pendingConfirmation {
        case .replaceTranscript:
            pendingConfirmation = nil
            startRecordingIfPossible()
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
        Task {
            await startRecordingFlow()
        }
    }

    private func startRecordingFlow() async {
        switch microphonePermissionManager.currentStatus() {
        case .authorized:
            beginRecording()

        case .notDetermined:
            state.session = .requestingPermission
            statusText = "Solicitando permiso de micrófono..."
            let granted = await microphonePermissionManager.requestAccess()
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
            state.error = Self.restrictedMicrophoneError
        }
    }

    /// Abre la sección de privacidad de Micrófono en Ajustes del Sistema.
    func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Abre la sección de privacidad de Accesibilidad en Ajustes del Sistema (donde se habilita
    /// Scribe para que el atajo global de Fn + Espacio funcione). Si el deep link no resuelve en esta
    /// versión de macOS, `NSWorkspace` simplemente no abre nada; no hay fallback porque no vale
    /// la pena mantener dos textos de ayuda ligeramente distintos para ese caso borde.
    func openAccessibilityPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Vuelve a consultar el estado del atajo global sin reiniciar el servicio. Se llama al
    /// volver a la app desde Ajustes del Sistema (Fase 6 de MVP3) y también puede ofrecerse como
    /// botón explícito ("Revisar permiso") para el mismo efecto.
    func refreshHotkeyStatus() {
        hotkeyStatus = globalHotkeyService.currentStatus()
    }

    /// Conecta la acción `openWindow` de SwiftUI con `WindowActivationServicing` (Fase 7 de
    /// MVP3), para el caso en que el atajo global se presiona después de que el usuario cerró la
    /// ventana principal del todo. `ContentView` llama esto una sola vez al aparecer, porque un
    /// servicio plano fuera de la jerarquía de vistas no tiene `@Environment` propio.
    func registerWindowReopenHandler(_ handler: @escaping () -> Void) {
        windowActivationService.registerReopenHandler(handler)
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
    /// cooperativa; comparar `currentTranscriptionAttempt` dentro de `transcribe(url:)` es lo
    /// que realmente evita que un resultado que llega tarde sobrescriba el estado ya revertido.
    func cancelTranscription() {
        guard state.session == .transcribing else { return }
        currentTranscriptionAttempt = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        state = steadyState()
        statusText = "Transcripción cancelada."
    }

    /// Actualiza tiempo transcurrido y nivel de entrada cada 200ms mientras se graba. Vive en
    /// un `Task` propio (en vez de `Timer`) para quedar en el mismo estilo async/await que el
    /// resto del view model.
    private func startMetering() {
        recordingElapsed = 0
        inputLevel = 0
        let start = Date()
        meterTask?.cancel()
        meterTask = Task {
            while !Task.isCancelled {
                recordingElapsed = Date().timeIntervalSince(start)
                inputLevel = audioRecorder.currentLevel()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
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
        let attemptID = UUID()
        currentTranscriptionAttempt = attemptID
        state.session = .transcribing
        statusText = "Transcribiendo..."
        do {
            let text = try await transcriptionService.transcribe(audioURL: url)
            guard currentTranscriptionAttempt == attemptID else { return }
            // TODO(modo append, post-MVP2): hoy cada transcripción reemplaza la anterior;
            // en algún momento se podría agregar un modo que concatene en vez de sobrescribir.
            transcript = text
            state.session = .idle
            state.error = nil
            statusText = "Transcripción lista."
            // El audio ya cumplió su propósito: se borra para no dejar WAVs temporales
            // acumulándose en disco más allá de lo necesario.
            audioRecorder.deleteCurrentFile()
            lastRecordingURL = nil
        } catch {
            guard currentTranscriptionAttempt == attemptID else { return }
            let appError = AppError(category: .transcription, underlying: error)
            state.session = .idle
            state.error = appError
            statusText = appError.message
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

    /// Vacía la transcripción y recalcula el estado real (no asume `.idle` sin más): si falta
    /// el modelo o el micrófono está bloqueado, el estado debe seguir reflejando eso.
    private func performClear() {
        transcript = ""
        state = steadyState()
        statusText = statusText(for: state)
    }
}
