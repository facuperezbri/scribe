import SwiftUI

/// Feedback visual mientras se está grabando: tiempo transcurrido, nivel de entrada del
/// micrófono (para confirmar que se está captando audio) y avisos por duración larga.
struct RecordingFeedbackView: View {
    let elapsed: TimeInterval
    let inputLevel: Float
    let warningText: String?
    let isStrongWarning: Bool

    private var formattedElapsed: String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: ScribeSpacing.sm) {
            HStack(spacing: ScribeSpacing.md) {
                Circle()
                    .fill(ScribeColors.recording)
                    .frame(width: 8, height: 8)

                Text(formattedElapsed)
                    .font(ScribeTypography.monoTimer)
                    .foregroundStyle(ScribeColors.inkSecondary)

                InputLevelMeter(level: inputLevel)
                    .frame(width: 100, height: 8)
            }

            if let warningText {
                Text(warningText)
                    .font(ScribeTypography.metadata)
                    .foregroundStyle(isStrongWarning ? ScribeColors.error : ScribeColors.warning)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recordingAccessibilityLabel)
    }

    private var recordingAccessibilityLabel: String {
        var parts = ["Grabando", formattedElapsed]
        if let warningText { parts.append(warningText) }
        return parts.joined(separator: ". ")
    }
}

/// Barra simple que refleja, en tiempo real, si el micrófono está recibiendo audio.
private struct InputLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ScribeColors.meterTrack)
                Capsule()
                    .fill(ScribeColors.meterFill)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(1, level))))
                    .animation(.linear(duration: ScribeMotion.meter), value: level)
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 24) {
        RecordingFeedbackView(elapsed: 12, inputLevel: 0.6, warningText: nil, isStrongWarning: false)
        RecordingFeedbackView(
            elapsed: 130,
            inputLevel: 0.3,
            warningText: "Grabación larga: la transcripción puede tardar más.",
            isStrongWarning: false
        )
        RecordingFeedbackView(
            elapsed: 320,
            inputLevel: 0.8,
            warningText: "Grabación muy larga: se recomienda detener y transcribir ahora.",
            isStrongWarning: true
        )
    }
    .padding()
}
