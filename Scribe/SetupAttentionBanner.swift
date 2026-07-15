import SwiftUI

/// Fila de atención compacta cuando falta configuración esencial: permisos o modelo local.
/// Una sola superficie liviana, no un banner por problema — legible en un vistazo.
struct SetupAttentionBanner: View {
    let issues: [SetupIssue]
    let onOpenMicrophoneSettings: () -> Void
    let onOpenInputMonitoringSettings: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onDownloadModel: () -> Void
    let onOpenAppleIntelligenceSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.xs) {
            ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                if index > 0 {
                    Divider().opacity(0.5)
                }
                issueRow(issue)
            }
        }
        .padding(.horizontal, ScribeSpacing.md)
        .padding(.vertical, ScribeSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScribeColors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: ScribeRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScribeRadius.control, style: .continuous)
                .stroke(ScribeColors.warning.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func issueRow(_ issue: SetupIssue) -> some View {
        HStack(spacing: ScribeSpacing.sm) {
            Image(systemName: icon(for: issue))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ScribeColors.warning)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(message(for: issue))
                .font(ScribeTypography.statusValue)
                .foregroundStyle(ScribeColors.ink)
                .lineLimit(2)

            Spacer(minLength: ScribeSpacing.sm)

            Button(actionTitle(for: issue), action: action(for: issue))
                .buttonStyle(.link)
                .font(ScribeTypography.statusValue)
        }
    }

    private func icon(for issue: SetupIssue) -> String {
        switch issue {
        case .microphoneDenied: return "mic.slash"
        case .inputMonitoringRequired: return "keyboard.badge.exclamationmark"
        case .accessibilityRequired: return "hand.raised"
        case .missingModel: return "arrow.down.circle"
        case .appleIntelligenceUnavailable: return "sparkles"
        }
    }

    private func message(for issue: SetupIssue) -> String {
        switch issue {
        case .microphoneDenied: return "Micrófono bloqueado"
        case .inputMonitoringRequired: return "Fn necesita permiso de Monitoreo de entrada"
        case .accessibilityRequired: return "Auto-pegado necesita permiso de Accesibilidad"
        case .missingModel: return "Modelo local no instalado"
        case .appleIntelligenceUnavailable: return "Reformateo necesita Apple Intelligence"
        }
    }

    private func actionTitle(for issue: SetupIssue) -> String {
        switch issue {
        case .microphoneDenied, .inputMonitoringRequired, .accessibilityRequired, .appleIntelligenceUnavailable:
            return "Abrir Ajustes"
        case .missingModel:
            return "Descargar"
        }
    }

    private func action(for issue: SetupIssue) -> () -> Void {
        switch issue {
        case .microphoneDenied: return onOpenMicrophoneSettings
        case .inputMonitoringRequired: return onOpenInputMonitoringSettings
        case .accessibilityRequired: return onOpenAccessibilitySettings
        case .missingModel: return onDownloadModel
        case .appleIntelligenceUnavailable: return onOpenAppleIntelligenceSettings
        }
    }
}

#Preview {
    SetupAttentionBanner(
        issues: [.inputMonitoringRequired, .missingModel],
        onOpenMicrophoneSettings: {},
        onOpenInputMonitoringSettings: {},
        onOpenAccessibilitySettings: {},
        onDownloadModel: {},
        onOpenAppleIntelligenceSettings: {}
    )
    .padding()
    .frame(width: 640)
}
