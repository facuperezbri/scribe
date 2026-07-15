import SwiftUI

/// Affordance de un solo uso, deliberadamente discreta: una fila liviana, no una tarjeta que
/// compita con la transcripción actual. No es historial — es un búfer temporal en memoria.
struct TranscriptRecoveryBanner: View {
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: ScribeSpacing.xxs) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ScribeColors.accent)
                .accessibilityHidden(true)

            Text("Transcripción anterior disponible")
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkSecondary)

            Text("·")
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkTertiary)

            Button("Recuperar", action: onRestore)
                .buttonStyle(.link)
                .font(ScribeTypography.metadata)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcripción anterior disponible")
        .accessibilityAction(named: "Recuperar", onRestore)
    }
}

#Preview {
    TranscriptRecoveryBanner(onRestore: {})
        .padding()
}
