import SwiftUI

/// Fase visual del motivo de onda/voz compartido entre la ventana principal y el overlay.
enum SpeechSignalPhase: Equatable {
    case idle
    case recording(level: Float)
    case transcribing
}

/// Firma visual de Scribe: barras redondeadas tipo trazo de pluma. En reposo son estáticas;
/// al grabar responden al nivel real del micrófono; al transcribir hacen una secuencia suave.
/// `compact` se usa en el overlay flotante; el tamaño estándar es el motivo hero de la
/// tarjeta principal de dictado.
struct SpeechSignalView: View {
    let phase: SpeechSignalPhase
    var activeColor: Color = ScribeColors.accent
    var trackColor: Color = ScribeColors.meterTrack
    var compact: Bool = false

    private var barCount: Int { compact ? 3 : 5 }
    private var barWidth: CGFloat { compact ? 3 : 8 }
    private var barSpacing: CGFloat { compact ? 3 : 12 }
    private var frameWidth: CGFloat { compact ? 18 : 132 }
    private var frameHeight: CGFloat { compact ? 13 : 76 }

    private static let phaseWeightsCompact: [CGFloat] = [0.4, 1.0, 0.65]
    private static let phaseWeightsHero: [CGFloat] = [0.35, 0.7, 1.0, 0.7, 0.35]
    private static let idleHeightsCompact: [CGFloat] = [6, 10, 7]
    private static let idleHeightsHero: [CGFloat] = [22, 38, 54, 38, 22]

    private var phaseWeights: [CGFloat] { compact ? Self.phaseWeightsCompact : Self.phaseWeightsHero }
    private var idleHeights: [CGFloat] { compact ? Self.idleHeightsCompact : Self.idleHeightsHero }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .frame(width: frameWidth, height: frameHeight, alignment: .bottom)
        .animation(.easeInOut(duration: ScribeMotion.meter), value: phase)
        .accessibilityHidden(true)
    }

    private func barHeight(for index: Int) -> CGFloat {
        switch phase {
        case .idle:
            return idleHeights[index]
        case .recording(let level):
            let base: CGFloat = compact ? 4 : 16
            let range: CGFloat = compact ? 9 : 44
            let boost = CGFloat(max(0, min(1, level))) * range
            return base + boost * phaseWeights[index]
        case .transcribing:
            return idleHeights[index] * 0.85
        }
    }

    private func barColor(for index: Int) -> Color {
        switch phase {
        case .idle:
            return activeColor.opacity(0.4)
        case .recording:
            return ScribeColors.recording
        case .transcribing:
            return activeColor.opacity(0.55)
        }
    }
}

/// Variante animada: agrega una secuencia en cascada mientras transcribe.
struct AnimatedSpeechSignalView: View {
    let phase: SpeechSignalPhase
    var activeColor: Color = ScribeColors.accent
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private var barCount: Int { compact ? 3 : 5 }
    private var barWidth: CGFloat { compact ? 3 : 8 }
    private var barSpacing: CGFloat { compact ? 3 : 12 }
    private var frameWidth: CGFloat { compact ? 18 : 132 }
    private var frameHeight: CGFloat { compact ? 13 : 76 }
    private var dotHeight: CGFloat { compact ? 8 : 30 }

    var body: some View {
        Group {
            if case .transcribing = phase, !reduceMotion {
                transcribingBars
            } else {
                SpeechSignalView(phase: phase, activeColor: activeColor, compact: compact)
            }
        }
    }

    private var transcribingBars: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(activeColor)
                    .frame(width: barWidth, height: dotHeight)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: ScribeMotion.transcribingDot)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * ScribeMotion.transcribingStagger),
                        value: isAnimating
                    )
            }
        }
        .frame(width: frameWidth, height: frameHeight, alignment: .bottom)
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}
