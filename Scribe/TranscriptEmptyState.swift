import SwiftUI

/// Estado vacío honesto: no hay historial, solo la última transcripción local.
struct TranscriptEmptyState: View {
    var body: some View {
        VStack(spacing: ScribeSpacing.sm) {
            Image(systemName: "text.quote")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(ScribeColors.accent)
                .accessibilityHidden(true)

            Text("Todavía no hay una transcripción")
                .font(ScribeTypography.body)
                .foregroundStyle(ScribeColors.ink)
                .multilineTextAlignment(.center)

            Text("Mantené Fn para hablar")
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ScribeSpacing.xxl)
        .padding(.horizontal, ScribeSpacing.lg)
        .scribeControlSurface()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TranscriptEmptyState()
        .padding()
        .frame(width: 420)
}
