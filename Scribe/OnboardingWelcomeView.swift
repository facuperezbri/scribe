import SwiftUI

/// Tarjeta de bienvenida mostrada una sola vez en el primer lanzamiento (ver
/// `DictationViewModel.showOnboardingWelcome`/`dismissOnboardingWelcome()`) para orientar a un
/// usuario nuevo sin necesidad de una pantalla o ventana propia: privacidad, permisos, y el atajo
/// global, en copy corto.
struct OnboardingWelcomeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.sm) {
            Text("Bienvenido a Scribe")
                .font(ScribeTypography.sectionTitle)
                .foregroundStyle(ScribeColors.ink)

            VStack(alignment: .leading, spacing: ScribeSpacing.xxs) {
                Text("Todo se procesa en esta Mac; nada se envía a servidores.")
                Text("Mantené Fn para dictar en cualquier app.")
                Text("Auto-pegado y Monitoreo de entrada requieren permisos del sistema.")
            }
            .font(ScribeTypography.body)
            .foregroundStyle(ScribeColors.inkSecondary)
            .accessibilityElement(children: .combine)

            Button("Entendido", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHint("Cierra la bienvenida y no la vuelve a mostrar")
        }
        .scribeCard()
    }
}

#Preview {
    OnboardingWelcomeView(onDismiss: {})
        .padding()
        .frame(width: 640)
}
