import SwiftUI

/// Ícono de la barra de menús: un símbolo distinto por estado amplio (reposo,
/// grabando, transcribiendo/ocupado, requiere atención). `MenuBarExtra` renderiza `Image(systemName:)`
/// como plantilla monocromática por defecto, así que se adapta sola a modo claro/oscuro sin tocar
/// color acá. No reutiliza el mapeo (con color) de `DictationStatusView`: a este tamaño alcanza con
/// una distinción más gruesa que la de `PrimaryState` completo.
struct MenuBarStatusIcon: View {
    @ObservedObject var viewModel: DictationViewModel

    private var systemImageName: String {
        switch viewModel.primaryState {
        case .recording:
            return "mic.fill"
        case .transcribing, .startingRecording, .stoppingRecording, .requestingPermission:
            return "ellipsis.circle"
        case .microphoneDenied, .missingModel, .inputMonitoringRequired, .error:
            return "exclamationmark.circle"
        case .downloadingModel:
            return "arrow.down.circle"
        case .ready, .transcriptReady:
            return "waveform"
        }
    }

    var body: some View {
        Image(systemName: systemImageName)
            .accessibilityLabel(viewModel.primaryStateTitle)
    }
}

/// Contenido del menú de la barra de menús: acciones rápidas de un utilitario en
/// background, todas delegando en `DictationViewModel` — el mismo punto de entrada centralizado
/// que ya usan el botón de la ventana principal y el atajo global, para no duplicar la lógica de
/// grabar/detener/transcribir.
struct MenuBarContentView: View {
    @ObservedObject var viewModel: DictationViewModel
    let onShowMainWindow: () -> Void

    var body: some View {
        Text("Estado actual: \(viewModel.primaryStateTitle)")

        if let autoPasteStatusText = viewModel.autoPasteStatusText {
            Text(autoPasteStatusText)
        }

        Divider()

        Button(viewModel.isRecording ? "Detener dictado" : "Iniciar dictado") {
            viewModel.handlePrimaryDictationAction(source: .menuBar)
        }
        .disabled(viewModel.isBusy)

        Button("Copiar última transcripción", action: viewModel.copyTranscript)
            .disabled(viewModel.transcript.isEmpty)

        Toggle(
            "Pegado automático",
            isOn: Binding(
                get: { viewModel.isAutoPasteEnabled },
                set: { viewModel.setAutoPasteEnabled($0) }
            )
        )

        Divider()

        Button("Mostrar Scribe", action: onShowMainWindow)

        if viewModel.isModelInstalled {
            Button("Abrir carpeta del modelo", action: viewModel.revealModelInFinder)
        }

        if viewModel.isMicrophonePermissionDenied {
            Button("Permiso de Micrófono...", action: viewModel.openMicrophonePrivacySettings)
        }

        if viewModel.hotkeyStatus == .inputMonitoringPermissionRequired {
            Button("Permiso de Monitoreo de entrada...", action: viewModel.openInputMonitoringPrivacySettings)
        }

        Divider()

        Button("Salir") {
            NSApplication.shared.terminate(nil)
        }
    }
}
