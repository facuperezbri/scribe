import SwiftUI

/// Contenido de la burbuja flotante: una cápsula compacta y oscura, sin cromo de
/// ventana, pensada para flotar por encima de lo que el usuario esté haciendo sin robarle
/// atención. Diseño propio — no reproduce el de ningún dictado-utility de terceros: en vez del
/// punto pulsante típico, usa tres barritas que responden al nivel real del micrófono.
struct RecordingOverlayView: View {
    let phase: RecordingOverlayPhase
    let elapsed: TimeInterval
    let inputLevel: Float
    /// Solo se usa en `.done`, para distinguir "transcripción lista" de "transcripción lista y ya
    /// pegada" (Fase 6). No decide nada del auto-paste, solo refleja lo que
    /// `DictationViewModel.lastAutoPasteResult` ya resolvió.
    let autoPasteResult: AutoPasteResult?

    private var formattedElapsed: String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var label: String {
        switch phase {
        case .hidden:
            return ""
        case .recording:
            return "Grabando \(formattedElapsed)"
        case .transcribing:
            return "Transcribiendo..."
        case .done:
            return autoPasteResult == .pasted ? "Pegado" : "Listo"
        }
    }

    var body: some View {
        HStack(spacing: ScribeSpacing.md) {
            indicator
            Text(label)
                .font(ScribeTypography.overlayLabel)
                .foregroundStyle(ScribeColors.overlayForeground)
                .fixedSize()
        }
        .padding(.horizontal, ScribeSpacing.lg)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(ScribeColors.overlayBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ScribeColors.overlayBorder)
        )
        .shadow(color: ScribeColors.overlayShadow, radius: 12, y: 4)
    }

    @ViewBuilder
    private var indicator: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .recording:
            SpeechSignalView(
                phase: .recording(level: inputLevel),
                activeColor: ScribeColors.recording,
                compact: true
            )
        case .transcribing:
            OverlayTranscribingIndicator()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ScribeColors.success)
        }
    }
}

/// Puntos en cascada para el overlay oscuro (contraste distinto al panel principal).
private struct OverlayTranscribingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(ScribeColors.overlayForeground.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .opacity(isAnimating && !reduceMotion ? 1 : 0.3)
                    .animation(
                        reduceMotion
                            ? .default
                            : .easeInOut(duration: ScribeMotion.transcribingDot)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * ScribeMotion.transcribingStagger),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 18, height: 13)
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        RecordingOverlayView(phase: .recording, elapsed: 12, inputLevel: 0.6, autoPasteResult: nil)
        RecordingOverlayView(phase: .transcribing, elapsed: 0, inputLevel: 0, autoPasteResult: nil)
        RecordingOverlayView(phase: .done, elapsed: 0, inputLevel: 0, autoPasteResult: nil)
        RecordingOverlayView(phase: .done, elapsed: 0, inputLevel: 0, autoPasteResult: .pasted)
    }
    .padding(40)
    .background(Color.gray)
}
