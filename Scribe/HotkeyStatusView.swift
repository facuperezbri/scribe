import SwiftUI

/// Estado del atajo global de Fn (mantener presionada), presentado de
/// forma subordinada al resto de la UI — mismo lugar y estilo que
/// `ModelStatusView`/`PrivacyNoteView`, no un banner que compita con el flujo principal de
/// grabar/detener.
struct HotkeyStatusView: View {
    let status: HotkeyStatus
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        switch status {
        case .unknown:
            EmptyView()
        case .active:
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Mantené Fn para grabar")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .inputMonitoringPermissionRequired:
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Para usar Fn desde cualquier app, Scribe necesita permiso de Monitoreo de entrada.")
                        .multilineTextAlignment(.center)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Activá Scribe en Ajustes del Sistema > Privacidad y seguridad > Monitoreo de entrada.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Button("Abrir Ajustes", action: onOpenSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Revisar permiso", action: onRefresh)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "keyboard.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(message)
                    .multilineTextAlignment(.center)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
