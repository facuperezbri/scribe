import SwiftUI

/// Estado del atajo global de Fn + Espacio (Fase 6 de MVP3, actualizado en Fase 9), presentado de
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
                Text("Fn + Espacio para grabar/detener")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .accessibilityPermissionRequired:
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Para usar Fn + Espacio desde cualquier app, Scribe necesita permiso de Accesibilidad.")
                        .multilineTextAlignment(.center)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Activá Scribe en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad.")
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
                Text(message)
                    .multilineTextAlignment(.center)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
