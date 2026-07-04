import AppKit
import Foundation

/// Estados posibles de la app.
enum AppState: Equatable {
    case requestingPermission
    case microphonePermissionDenied
    case ready
    case recording
    case stoppingRecording
    case transcribing
    case transcriptReady
    case missingModel
    case downloadingModel
    case error(AppError)
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

@MainActor
final class DictationViewModel: ObservableObject {
    @Published var state: AppState = .ready
    @Published var statusText: String = "Listo"
    @Published var transcript: String = "" {
        didSet { persistTranscript() }
    }
    @Published var downloadProgress: Double = 0
    @Published var showCopiedFeedback = false
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var recordingElapsed: TimeInterval = 0
    @Published var inputLevel: Float = 0

    private let audioRecorder: AudioRecordingServicing
    private let transcriptionService: TranscriptionServicing
    private let modelManager: ModelManaging
    private let microphonePermissionManager: MicrophonePermissionManaging
    private let clipboardService: ClipboardServicing
    private let transcriptStore: TranscriptStoring
    private(set) var lastRecordingURL: URL?
    private var meterTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var pendingTranscriptSaveTask: Task<Void, Never>?
    /// Autoritativo para descartar un resultado de transcripción que llega tarde tras
    /// cancelar: `transcriptionTask?.cancel()` es solo un intento cooperativo (WhisperKit no
    /// garantiza abortar la inferencia a mitad de camino), así que no alcanza por sí solo.
    private var isTranscriptionCancelled = false
    /// Cierra la ventana entre tocar "Grabar" (camino ya autorizado, sin estado intermedio
    /// publicado) y que `beginRecording()` corra de verdad: sin esto, un doble clic muy rápido
    /// puede disparar dos grabaciones que se pisan entre sí.
    private var isStartingRecording = false

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
        transcriptionService: TranscriptionServicing? = nil
    ) {
        self.audioRecorder = audioRecorder
        self.modelManager = modelManager
        self.microphonePermissionManager = microphonePermissionManager
        self.clipboardService = clipboardService
        self.transcriptStore = transcriptStore
        self.transcriptionService = transcriptionService ?? TranscriptionService(modelManager: modelManager)

        if let saved = transcriptStore.loadTranscript(), !saved.isEmpty {
            transcript = saved
        }
        state = currentSteadyState()
        statusText = statusText(forSteadyState: state)
    }

    /// Estado "en reposo" real para el contenido actual: como `baseReadyState()`, pero
    /// además refleja si ya hay una transcripción para mostrar. Única fuente de verdad para
    /// volver a un estado neutral (al iniciar la app, limpiar o cancelar una transcripción).
    private func currentSteadyState() -> AppState {
        let base = baseReadyState()
        return (!transcript.isEmpty && base == .ready) ? .transcriptReady : base
    }

    /// Estado "en reposo" a partir solo del modelo instalado y el permiso de micrófono
    /// vigente, sin considerar si hay transcripción. Usado por `currentSteadyState()`.
    private func baseReadyState() -> AppState {
        guard modelManager.isModelInstalled else { return .missingModel }
        switch microphonePermissionManager.currentStatus() {
        case .denied:
            return .microphonePermissionDenied
        case .restricted:
            return .error(Self.restrictedMicrophoneError)
        case .authorized, .notDetermined:
            return .ready
        }
    }

    private func statusText(forSteadyState state: AppState) -> String {
        switch state {
        case .ready:
            return "Listo"
        case .transcriptReady:
            return "Transcripción restaurada. Listo para grabar de nuevo."
        case .missingModel:
            return "Modelo no instalado. Podés grabar, pero necesitás descargarlo para transcribir."
        case .microphonePermissionDenied:
            return "Micrófono bloqueado. Habilitalo en Ajustes del Sistema para poder grabar."
        case .error(let appError):
            return appError.message
        default:
            return "Listo"
        }
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
        switch state {
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

    var isError: Bool {
        switch state {
        case .error, .microphonePermissionDenied:
            return true
        default:
            return false
        }
    }

    var statusKind: StatusKind {
        switch state {
        case .ready, .transcriptReady:
            return .neutral
        case .recording, .stoppingRecording, .transcribing, .downloadingModel, .requestingPermission:
            return .active
        case .missingModel:
            return .warning
        case .microphonePermissionDenied, .error:
            return .error
        }
    }

    var isBusy: Bool {
        switch state {
        case .transcribing, .downloadingModel, .requestingPermission, .stoppingRecording:
            return true
        default:
            return false
        }
    }

    /// `nil` si la grabación todavía no es larga, o el aviso correspondiente al umbral
    /// alcanzado. Solo tiene sentido mientras se está grabando.
    var recordingWarningText: String? {
        guard state == .recording else { return nil }
        if recordingElapsed >= Self.strongWarningThreshold {
            return "Grabación muy larga: se recomienda detener y transcribir ahora."
        }
        if recordingElapsed >= Self.softWarningThreshold {
            return "Grabación larga: la transcripción puede tardar más."
        }
        return nil
    }

    var isStrongRecordingWarning: Bool {
        state == .recording && recordingElapsed >= Self.strongWarningThreshold
    }

    /// Punto único de entrada del botón Grabar/Detener. La guarda contra `isBusy` evita que
    /// clics rápidos repetidos disparen una grabación o detención inválida mientras la app
    /// está en un estado transitorio (deteniendo, transcribiendo, descargando, pidiendo permiso).
    /// Si ya hay una transcripción, grabar de nuevo la reemplazaría en silencio: se pide
    /// confirmación antes de arrancar.
    func toggleRecording() {
        guard !isBusy, pendingConfirmation == nil else { return }
        switch state {
        case .recording:
            stopRecording()
        default:
            if !transcript.isEmpty {
                pendingConfirmation = .replaceTranscript
            } else {
                startRecordingIfPossible()
            }
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

    /// Único punto de entrada real hacia `startRecordingFlow()`. La guarda contra
    /// `isStartingRecording` cierra la ventana de carrera del camino ya autorizado: entre
    /// tocar "Grabar" y que `beginRecording()` deje el estado en `.recording` no hay ningún
    /// `AppState` publicado que bloquee un segundo toque, así que sin este flag un doble clic
    /// muy rápido podía arrancar dos grabaciones que se pisan.
    private func startRecordingIfPossible() {
        guard !isStartingRecording else { return }
        isStartingRecording = true
        Task {
            await startRecordingFlow()
            isStartingRecording = false
        }
    }

    func cancelPendingConfirmation() {
        pendingConfirmation = nil
    }

    private func startRecordingFlow() async {
        switch microphonePermissionManager.currentStatus() {
        case .authorized:
            beginRecording()

        case .notDetermined:
            state = .requestingPermission
            statusText = "Solicitando permiso de micrófono..."
            let granted = await microphonePermissionManager.requestAccess()
            if granted {
                beginRecording()
            } else {
                state = .microphonePermissionDenied
                statusText = "Permiso de micrófono denegado. Habilitalo en Ajustes del Sistema para poder grabar."
            }

        case .denied:
            state = .microphonePermissionDenied
            statusText = "Micrófono bloqueado. Habilitalo en Ajustes del Sistema para poder grabar."

        case .restricted:
            state = .error(Self.restrictedMicrophoneError)
        }
    }

    /// Abre la sección de privacidad de Micrófono en Ajustes del Sistema.
    func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    private func beginRecording() {
        do {
            let fileURL = try audioRecorder.startRecording()
            lastRecordingURL = fileURL
            state = .recording
            statusText = "Grabando..."
            startMetering()
        } catch {
            let appError = AppError(category: .recording, underlying: error)
            state = .error(appError)
            statusText = appError.message
        }
    }

    private func stopRecording() {
        // Estado transitorio fijado de forma sincrónica: bloquea un segundo tap antes de
        // que audioRecorder.stopRecording() termine, evitando una doble detención/transcripción.
        stopMetering()
        state = .stoppingRecording
        statusText = "Deteniendo grabación..."

        guard let url = audioRecorder.stopRecording() else {
            let appError = AppError(category: .recording, message: "No se encontró el audio grabado.")
            state = .error(appError)
            statusText = appError.message
            return
        }
        lastRecordingURL = url

        guard modelManager.isModelInstalled else {
            state = .missingModel
            statusText = "Modelo no instalado. Descargalo para transcribir tu grabación."
            return
        }

        transcriptionTask = Task { await transcribe(url: url) }
    }

    /// Cancela la transcripción en curso. `transcriptionTask?.cancel()` es solo una señal
    /// cooperativa; el guard de `isTranscriptionCancelled` dentro de `transcribe(url:)` es lo
    /// que realmente evita que un resultado que llega tarde sobrescriba el estado ya revertido.
    func cancelTranscription() {
        guard state == .transcribing else { return }
        isTranscriptionCancelled = true
        transcriptionTask?.cancel()
        transcriptionTask = nil
        state = currentSteadyState()
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

    private func transcribe(url: URL) async {
        state = .transcribing
        statusText = "Transcribiendo..."
        isTranscriptionCancelled = false
        do {
            let text = try await transcriptionService.transcribe(audioURL: url)
            guard !isTranscriptionCancelled else { return }
            // TODO(modo append, post-MVP2): hoy cada transcripción reemplaza la anterior;
            // en algún momento se podría agregar un modo que concatene en vez de sobrescribir.
            transcript = text
            state = .transcriptReady
            statusText = "Transcripción lista."
            // El audio ya cumplió su propósito: se borra para no dejar WAVs temporales
            // acumulándose en disco más allá de lo necesario.
            audioRecorder.deleteCurrentFile()
            lastRecordingURL = nil
        } catch {
            guard !isTranscriptionCancelled else { return }
            let appError = AppError(category: .transcription, underlying: error)
            state = .error(appError)
            statusText = appError.message
        }
        transcriptionTask = nil
    }

    /// Descarga del modelo iniciada explícitamente por el usuario (botón "Descargar modelo").
    /// Este es el único lugar de la app donde se dispara una descarga de red.
    func downloadModel() {
        guard !isBusy else { return }
        state = .downloadingModel
        downloadProgress = 0
        statusText = "Descargando modelo... 0%"
        Task {
            do {
                _ = try await modelManager.downloadModel { [weak self] fraction in
                    Task { @MainActor in
                        self?.downloadProgress = fraction
                        self?.statusText = "Descargando modelo... \(Int(fraction * 100))%"
                    }
                }
                transcriptionService.invalidate()
                if let url = lastRecordingURL {
                    await transcribe(url: url)
                } else {
                    state = .ready
                    statusText = "Modelo instalado. Listo."
                }
            } catch {
                let appError = AppError(category: .model, underlying: error)
                state = .missingModel
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

    /// Vacía la transcripción y recalcula el estado real (no asume `.ready`): si falta el
    /// modelo o el micrófono está bloqueado, el estado debe seguir reflejando eso.
    private func performClear() {
        transcript = ""
        state = currentSteadyState()
        statusText = statusText(forSteadyState: state)
    }
}
