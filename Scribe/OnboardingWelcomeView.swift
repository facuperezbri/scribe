import SwiftUI

/// Tarjeta de bienvenida mostrada una sola vez en el primer lanzamiento (ver
/// `DictationViewModel.showOnboardingWelcome`/`dismissOnboardingWelcome()`) para orientar a un
/// usuario nuevo sin necesidad de una pantalla o ventana propia: privacidad, permisos, y el atajo
/// global, en tres líneas.
struct OnboardingWelcomeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bienvenido a Scribe")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Todo el audio y el texto se procesan en esta Mac; nada se envía a servidores.")
                Text("Otorgá permiso de Micrófono y de Accesibilidad para dictar desde cualquier app.")
                Text("Usá Fn + Espacio para empezar y detener la grabación.")
            }
            .accessibilityElement(children: .combine)

            Button("Entendido", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .cardBackground()
    }
}

#Preview {
    OnboardingWelcomeView(onDismiss: {})
        .padding()
}
