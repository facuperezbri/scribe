import SwiftUI

/// Contenido de la burbuja flotante (Fase 5 de MVP4): una cápsula compacta y oscura, sin cromo de
/// ventana, pensada para flotar por encima de lo que el usuario esté haciendo sin robarle
/// atención. Diseño propio — no reproduce el de ningún dictado-utility de terceros: en vez del
/// punto pulsante típico, usa tres barritas que responden al nivel real del micrófono.
struct RecordingOverlayView: View {
    let phase: RecordingOverlayPhase
    let elapsed: TimeInterval
    let inputLevel: Float

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
            return "Listo"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    @ViewBuilder
    private var indicator: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .recording:
            RecordingLevelIndicator(level: inputLevel)
        case .transcribing:
            TranscribingIndicator()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

/// Tres barritas que responden al nivel de entrada del micrófono en vez de un punto pulsante
/// genérico, para que la burbuja tenga una firma visual propia y además confirme, de un vistazo,
/// que el micrófono está captando audio.
private struct RecordingLevelIndicator: View {
    let level: Float

    private static let phaseWeights: [CGFloat] = [0.4, 1.0, 0.65]

    private func barHeight(_ index: Int) -> CGFloat {
        let base: CGFloat = 4
        let boost = CGFloat(max(0, min(1, level))) * 9
        return base + boost * Self.phaseWeights[index]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .frame(width: 18, height: 13)
        .animation(.easeInOut(duration: 0.12), value: level)
    }
}

/// Tres puntos con opacidad animada en cascada para "transcribiendo", en vez de un
/// `ProgressView` circular que a este tamaño compacto se ve borroso.
private struct TranscribingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 18, height: 13)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    VStack(spacing: 16) {
        RecordingOverlayView(phase: .recording, elapsed: 12, inputLevel: 0.6)
        RecordingOverlayView(phase: .transcribing, elapsed: 0, inputLevel: 0)
        RecordingOverlayView(phase: .done, elapsed: 0, inputLevel: 0)
    }
    .padding(40)
    .background(Color.gray)
}
