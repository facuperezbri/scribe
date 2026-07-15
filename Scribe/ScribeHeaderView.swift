import SwiftUI

/// Barra de identidad: marca, un estado en vivo, la garantía de privacidad local y el
/// menú de ajustes. Deliberadamente simple — sin chips de modelo ni texto largo.
struct ScribeHeaderView: View {
    @ObservedObject var viewModel: DictationViewModel

    var body: some View {
        HStack(alignment: .center, spacing: ScribeSpacing.md) {
            HStack(spacing: ScribeSpacing.xs) {
                Image(systemName: "waveform")
                    .foregroundStyle(ScribeColors.accent)
                    .accessibilityHidden(true)
                Text("Scribe")
                    .fontWeight(.semibold)
            }
            .font(ScribeTypography.brand)
            .foregroundStyle(ScribeColors.ink)

            Spacer(minLength: ScribeSpacing.sm)

            Text(stateLabel)
                .font(ScribeTypography.statusValue)
                .foregroundStyle(stateLabelColor)
                .lineLimit(1)

            HStack(spacing: ScribeSpacing.xxs) {
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)
                Text("Local")
            }
            .font(ScribeTypography.metadata)
            .foregroundStyle(ScribeColors.inkTertiary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Todo se procesa en esta Mac")

            ScribeSettingsMenu(viewModel: viewModel)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }

    private var stateLabel: String {
        switch viewModel.primaryState {
        case .ready:
            return "Listo para dictar"
        case .recording:
            return "Grabando"
        case .transcribing:
            return "Transcribiendo"
        case .transcriptReady:
            return "Transcripción lista"
        case .startingRecording, .stoppingRecording, .requestingPermission:
            return "Dictado local activo"
        case .downloadingModel:
            return "Descargando modelo…"
        default:
            return viewModel.primaryStateTitle
        }
    }

    private var stateLabelColor: Color {
        switch viewModel.primaryState {
        case .recording:
            return ScribeColors.recording
        case .transcribing, .startingRecording, .stoppingRecording, .requestingPermission, .downloadingModel:
            return ScribeColors.processing
        case .microphoneDenied, .error:
            return ScribeColors.error
        case .missingModel, .inputMonitoringRequired:
            return ScribeColors.warning
        case .ready, .transcriptReady:
            return ScribeColors.inkSecondary
        }
    }
}

/// Menú compacto de ajustes: atajo, auto-pegado, carpeta del modelo y salir.
struct ScribeSettingsMenu: View {
    @ObservedObject var viewModel: DictationViewModel

    var body: some View {
        Menu {
            Section("Atajo") {
                Text("Fn — mantener para hablar")
                    .disabled(true)
                Text("Doble toque — modo manos libres")
                    .disabled(true)
            }

            Section("Pegado") {
                Toggle(
                    "Pegado automático",
                    isOn: Binding(
                        get: { viewModel.isAutoPasteEnabled },
                        set: { viewModel.setAutoPasteEnabled($0) }
                    )
                )
            }

            Section("Reformateo") {
                Toggle(
                    "Reformatear con Apple Intelligence",
                    isOn: Binding(
                        get: { viewModel.isFormattingEnabled },
                        set: { viewModel.setFormattingEnabled($0) }
                    )
                )
                if viewModel.isFormattingEnabled {
                    Picker(
                        "Perfil",
                        selection: Binding(
                            get: { viewModel.formattingProfile },
                            set: { viewModel.setFormattingProfile($0) }
                        )
                    ) {
                        ForEach(FormattingProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    if !viewModel.isAppleIntelligenceAvailable {
                        Button("Abrir Ajustes de Apple Intelligence…", action: viewModel.openAppleIntelligencePrivacySettings)
                    }
                }
            }

            Section("Permisos") {
                Button("Micrófono…", action: viewModel.openMicrophonePrivacySettings)
                Button("Monitoreo de entrada…", action: viewModel.openInputMonitoringPrivacySettings)
                if viewModel.isAutoPasteEnabled {
                    Button("Accesibilidad…", action: viewModel.openAccessibilityPrivacySettings)
                }
            }

            if viewModel.isModelInstalled {
                Section("Modelo") {
                    Button("Abrir carpeta del modelo", action: viewModel.revealModelInFinder)
                }
            } else if !viewModel.isDownloadingModel {
                Section("Modelo") {
                    Button("Descargar modelo local", action: viewModel.downloadModel)
                }
            }

            Divider()

            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ScribeColors.inkSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Ajustes")
    }
}

#Preview {
    ScribeHeaderView(viewModel: DictationViewModel())
        .padding()
}
