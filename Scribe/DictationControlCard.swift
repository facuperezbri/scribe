import SwiftUI

/// Tarjeta hero de la ventana principal: el motivo de voz de Scribe, el estado de dictado en
/// letra grande, el atajo Fn y una acción de respaldo para grabar con el mouse. Es el módulo
/// de mayor autoridad visual de la ventana.
struct DictationControlCard: View {
    @ObservedObject var viewModel: DictationViewModel

    private var signalPhase: SpeechSignalPhase {
        switch viewModel.primaryState {
        case .recording:
            return .recording(level: viewModel.inputLevel)
        case .transcribing:
            return .transcribing
        default:
            return .idle
        }
    }

    var body: some View {
        VStack(spacing: ScribeSpacing.lg) {
            AnimatedSpeechSignalView(phase: signalPhase)
                .frame(maxWidth: .infinity)

            VStack(spacing: ScribeSpacing.xs) {
                Text(viewModel.primaryStateTitle)
                    .font(ScribeTypography.primaryState)
                    .foregroundStyle(ScribeColors.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let hint = viewModel.primaryStateHint {
                    Text(hint)
                        .font(ScribeTypography.body)
                        .foregroundStyle(ScribeColors.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(controlCardAccessibilityLabel)

            if viewModel.isRecording {
                RecordingFeedbackView(
                    elapsed: viewModel.recordingElapsed,
                    inputLevel: viewModel.inputLevel,
                    warningText: viewModel.recordingWarningText,
                    isStrongWarning: viewModel.isStrongRecordingWarning
                )
            }

            if viewModel.isTranscribing {
                TranscribingFeedbackView(onCancel: viewModel.cancelTranscription)
            } else {
                VStack(spacing: ScribeSpacing.sm) {
                    HStack(spacing: ScribeSpacing.xs) {
                        FnKeycapView()
                        Text("para hablar")
                            .font(ScribeTypography.body)
                            .foregroundStyle(ScribeColors.inkSecondary)
                    }

                    Text("Dictá en cualquier app. Scribe pega el texto automáticamente.")
                        .font(ScribeTypography.metadata)
                        .foregroundStyle(ScribeColors.inkTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: { viewModel.handlePrimaryDictationAction() }) {
                    HStack(spacing: ScribeSpacing.xs) {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        Text(viewModel.recordButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(viewModel.isRecording ? ScribeColors.recording : ScribeColors.accent)
                .controlSize(.large)
                .disabled(viewModel.isBusy)
                .accessibilityLabel(viewModel.isRecording ? "Detener grabación" : "Grabar con el mouse")
                .accessibilityHint(viewModel.isRecording ? "" : "Alternativa al atajo Fn")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controlCardAccessibilityLabel: String {
        if let hint = viewModel.primaryStateHint {
            return "\(viewModel.primaryStateTitle). \(hint). Atajo Fn."
        }
        return "\(viewModel.primaryStateTitle). Atajo Fn."
    }
}

/// Representación visual de la tecla Fn.
struct FnKeycapView: View {
    var body: some View {
        Text("fn")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ScribeColors.ink)
            .padding(.horizontal, ScribeSpacing.sm)
            .padding(.vertical, ScribeSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ScribeColors.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ScribeColors.borderStrong, lineWidth: 1)
            )
            .accessibilityLabel("Atajo: Fn")
    }
}

#Preview {
    DictationControlCard(viewModel: DictationViewModel())
        .padding()
        .frame(width: 304)
        .scribeCard()
}
