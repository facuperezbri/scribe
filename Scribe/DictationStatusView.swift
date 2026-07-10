import SwiftUI

/// Área central de la ventana compacta (Fase 8): un ícono grande y un título fijo por
/// `PrimaryState`, con el detalle de grabación/transcripción ya existente (`RecordingFeedbackView`,
/// `TranscribingFeedbackView`) anidado adentro en vez de repetido como hermano en `ContentView`,
/// y un botón de "Copiar" destacado cuando la transcripción está lista — es el único punto de
/// la ventana que cambia de forma notoria según el estado, para que grabar/transcribir no
/// dependan de leer texto chico.
struct DictationStatusView: View {
    let primaryState: PrimaryState
    let title: String
    let hint: String?
    let elapsed: TimeInterval
    let inputLevel: Float
    let warningText: String?
    let isStrongWarning: Bool
    let onCancelTranscribing: () -> Void
    let showCopyCallToAction: Bool
    let showCopiedFeedback: Bool
    let onCopy: () -> Void

    @State private var isPulsing = false

    private var isRecording: Bool { primaryState == .recording }
    private var isTranscribing: Bool { primaryState == .transcribing }

    private var icon: String {
        switch primaryState {
        case .ready, .transcriptReady: return "waveform"
        case .startingRecording, .requestingPermission, .stoppingRecording: return "ellipsis.circle"
        case .recording: return "mic.fill"
        case .transcribing: return "text.bubble"
        case .microphoneDenied: return "mic.slash"
        case .missingModel, .downloadingModel: return "arrow.down.circle"
        case .accessibilityRequired: return "keyboard.badge.exclamationmark"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch primaryState {
        case .ready, .transcriptReady: return .accentColor
        case .startingRecording, .requestingPermission, .stoppingRecording, .transcribing, .downloadingModel:
            return .blue
        case .recording: return .red
        case .missingModel, .accessibilityRequired: return .orange
        case .microphoneDenied, .error: return .red
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(iconColor)
                .scaleEffect(isPulsing ? 1.12 : 1.0)
                .animation(
                    isRecording ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                    value: isPulsing
                )
                .onAppear { isPulsing = isRecording }
                .onChange(of: isRecording) { isPulsing = $0 }

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isRecording {
                RecordingFeedbackView(
                    elapsed: elapsed,
                    inputLevel: inputLevel,
                    warningText: warningText,
                    isStrongWarning: isStrongWarning
                )
            }

            if isTranscribing {
                TranscribingFeedbackView(onCancel: onCancelTranscribing)
            }

            if showCopyCallToAction {
                Button(showCopiedFeedback ? "Copiado" : "Copiar", action: onCopy)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

#Preview {
    VStack(spacing: 20) {
        DictationStatusView(
            primaryState: .ready,
            title: "Listo para dictar",
            hint: "Presioná Fn + Espacio para dictar",
            elapsed: 0,
            inputLevel: 0,
            warningText: nil,
            isStrongWarning: false,
            onCancelTranscribing: {},
            showCopyCallToAction: false,
            showCopiedFeedback: false,
            onCopy: {}
        )
        DictationStatusView(
            primaryState: .recording,
            title: "Grabando...",
            hint: nil,
            elapsed: 12,
            inputLevel: 0.6,
            warningText: nil,
            isStrongWarning: false,
            onCancelTranscribing: {},
            showCopyCallToAction: false,
            showCopiedFeedback: false,
            onCopy: {}
        )
        DictationStatusView(
            primaryState: .transcriptReady,
            title: "Transcripción lista",
            hint: nil,
            elapsed: 0,
            inputLevel: 0,
            warningText: nil,
            isStrongWarning: false,
            onCancelTranscribing: {},
            showCopyCallToAction: true,
            showCopiedFeedback: false,
            onCopy: {}
        )
    }
    .padding()
}
