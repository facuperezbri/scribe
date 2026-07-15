import SwiftUI

/// Franja silenciosa de salud del sistema: modelo, micrófono, accesibilidad, auto-pegado,
/// reformateo y privacidad. Pares breves de etiqueta/valor, pensados para leerse en 1-2
/// segundos — no un panel técnico con párrafos.
struct SystemStatusFooter: View {
    @ObservedObject var viewModel: DictationViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            StatusItem(
                icon: "cpu",
                label: "Modelo",
                value: modelValue,
                tint: modelTint,
                actionTitle: modelActionTitle,
                action: modelAction
            )

            Divider()

            StatusItem(
                icon: microphoneIcon,
                label: "Micrófono",
                value: microphoneValue,
                tint: microphoneTint,
                actionTitle: microphoneActionTitle,
                action: microphoneAction
            )

            Divider()

            StatusItem(
                icon: "hand.raised",
                label: "Accesibilidad",
                value: accessibilityValue,
                tint: accessibilityTint,
                actionTitle: accessibilityActionTitle,
                action: accessibilityAction
            )

            Divider()

            autoPasteItem

            Divider()

            formattingItem

            Divider()

            StatusItem(
                icon: "lock.shield",
                label: "Privacidad",
                value: "100% local",
                tint: ScribeColors.success
            )
        }
        .frame(maxWidth: .infinity)
        .scribeQuietSurface()
    }

    private var formattingItem: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.xxs) {
            Label("Reformateo", systemImage: "wand.and.stars")
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkSecondary)

            Toggle(
                viewModel.isFormattingEnabled ? "Activado" : "Desactivado",
                isOn: Binding(
                    get: { viewModel.isFormattingEnabled },
                    set: { viewModel.setFormattingEnabled($0) }
                )
            )
            .font(ScribeTypography.statusValue)
            .foregroundStyle(viewModel.isFormattingEnabled ? ScribeColors.success : ScribeColors.inkSecondary)
            .toggleStyle(.switch)
            .controlSize(.small)

            if viewModel.isFormattingEnabled, !viewModel.isAppleIntelligenceAvailable {
                Text(viewModel.appleIntelligenceUnavailableReason?.message ?? "Apple Intelligence no disponible")
                    .font(ScribeTypography.metadata)
                    .foregroundStyle(ScribeColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ScribeSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reformateo: \(viewModel.isFormattingEnabled ? "activado" : "desactivado")")
    }

    private var autoPasteItem: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.xxs) {
            Label("Auto-pegado", systemImage: "doc.on.clipboard")
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkSecondary)

            Toggle(
                viewModel.isAutoPasteEnabled ? "Activado" : "Desactivado",
                isOn: Binding(
                    get: { viewModel.isAutoPasteEnabled },
                    set: { viewModel.setAutoPasteEnabled($0) }
                )
            )
            .font(ScribeTypography.statusValue)
            .foregroundStyle(viewModel.isAutoPasteEnabled ? ScribeColors.success : ScribeColors.inkSecondary)
            .toggleStyle(.switch)
            .controlSize(.small)

            if let autoPasteStatusText = viewModel.autoPasteStatusText {
                Text(autoPasteStatusText)
                    .font(ScribeTypography.metadata)
                    .foregroundStyle(ScribeColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ScribeSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Auto-pegado: \(viewModel.isAutoPasteEnabled ? "activado" : "desactivado")")
    }

    // MARK: - Model

    private var modelValue: String {
        if viewModel.isDownloadingModel {
            return "Descargando \(Int(viewModel.downloadProgress * 100))%"
        }
        return viewModel.isModelInstalled ? "Listo" : "No instalado"
    }

    private var modelTint: Color {
        if viewModel.isDownloadingModel { return ScribeColors.processing }
        return viewModel.isModelInstalled ? ScribeColors.success : ScribeColors.warning
    }

    private var modelActionTitle: String? {
        if viewModel.isDownloadingModel { return nil }
        return viewModel.isModelInstalled ? "Ver en Finder" : "Descargar"
    }

    private var modelAction: (() -> Void)? {
        if viewModel.isDownloadingModel { return nil }
        if viewModel.isModelInstalled {
            return { viewModel.revealModelInFinder() }
        }
        return { viewModel.downloadModel() }
    }

    // MARK: - Microphone

    private var microphoneIcon: String {
        switch viewModel.state.permission {
        case .denied, .restricted: return "mic.slash"
        default: return "mic.fill"
        }
    }

    private var microphoneValue: String {
        switch viewModel.state.permission {
        case .authorized: return "Listo"
        case .notDetermined: return "Pendiente"
        case .denied: return "Bloqueado"
        case .restricted: return "Restringido"
        }
    }

    private var microphoneTint: Color {
        switch viewModel.state.permission {
        case .authorized: return ScribeColors.success
        case .notDetermined: return ScribeColors.inkSecondary
        case .denied, .restricted: return ScribeColors.error
        }
    }

    private var microphoneActionTitle: String? {
        viewModel.isMicrophonePermissionDenied ? "Abrir Ajustes" : nil
    }

    private var microphoneAction: (() -> Void)? {
        guard viewModel.isMicrophonePermissionDenied else { return nil }
        return { viewModel.openMicrophonePrivacySettings() }
    }

    // MARK: - Accessibility

    private var accessibilityValue: String {
        if !viewModel.isAutoPasteEnabled { return "No requerida" }
        return viewModel.isAccessibilityPermissionGranted ? "Lista" : "Permiso requerido"
    }

    private var accessibilityTint: Color {
        if !viewModel.isAutoPasteEnabled { return ScribeColors.inkSecondary }
        return viewModel.isAccessibilityPermissionGranted ? ScribeColors.success : ScribeColors.warning
    }

    private var accessibilityActionTitle: String? {
        guard viewModel.isAutoPasteEnabled, !viewModel.isAccessibilityPermissionGranted else { return nil }
        return "Abrir Ajustes"
    }

    private var accessibilityAction: (() -> Void)? {
        guard viewModel.isAutoPasteEnabled, !viewModel.isAccessibilityPermissionGranted else { return nil }
        return { viewModel.openAccessibilityPrivacySettings() }
    }
}

/// Par de etiqueta/valor compacto para una señal del sistema, con acción opcional cuando
/// requiere atención.
private struct StatusItem: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = ScribeColors.inkSecondary
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.xxs) {
            Label(label, systemImage: icon)
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkSecondary)
                .accessibilityHidden(true)

            Text(value)
                .font(ScribeTypography.statusValue)
                .foregroundStyle(tint)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(ScribeTypography.metadata)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ScribeSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview {
    SystemStatusFooter(viewModel: DictationViewModel())
        .padding()
        .frame(width: 780)
}
