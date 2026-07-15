import SwiftUI

/// Ventana principal rediseñada: un centro de control calmo con tres zonas — identidad,
/// dictado + transcripción, y salud del sistema. No es la superficie donde ocurre el dictado
/// diario (eso pasa en segundo plano con Fn); es para confianza, visibilidad, recuperación y
/// configuración.
struct ScribeMainView: View {
    @ObservedObject var viewModel: DictationViewModel
    @Environment(\.scenePhase) private var scenePhase

    private let heroWidth: CGFloat = 304

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScribeSpacing.xl) {
                ScribeHeaderView(viewModel: viewModel)

                if viewModel.showOnboardingWelcome {
                    OnboardingWelcomeView(onDismiss: viewModel.dismissOnboardingWelcome)
                }

                if !viewModel.setupIssues.isEmpty {
                    SetupAttentionBanner(
                        issues: viewModel.setupIssues,
                        onOpenMicrophoneSettings: viewModel.openMicrophonePrivacySettings,
                        onOpenInputMonitoringSettings: viewModel.openInputMonitoringPrivacySettings,
                        onOpenAccessibilitySettings: viewModel.openAccessibilityPrivacySettings,
                        onDownloadModel: viewModel.downloadModel,
                        onOpenAppleIntelligenceSettings: viewModel.openAppleIntelligencePrivacySettings
                    )
                }

                HStack(alignment: .top, spacing: ScribeSpacing.xl) {
                    DictationControlCard(viewModel: viewModel)
                        .frame(width: heroWidth)
                        .scribeCard()

                    LastTranscriptCard(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }

                SystemStatusFooter(viewModel: viewModel)
            }
            .padding(ScribeSpacing.xxl)
        }
        .background(ScribeColors.windowBackground)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 620, idealHeight: 680)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.refreshSystemPermissions()
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: isPendingConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(confirmationActionTitle, role: .destructive) {
                viewModel.confirmPendingAction()
            }
            Button("Cancelar", role: .cancel) {
                viewModel.cancelPendingConfirmation()
            }
        }
    }

    private var isPendingConfirmationPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented { viewModel.cancelPendingConfirmation() }
            }
        )
    }

    private var confirmationTitle: String {
        switch viewModel.pendingConfirmation {
        case .clearTranscript:
            return "Se va a borrar la transcripción actual. Esta acción no se puede deshacer."
        case nil:
            return ""
        }
    }

    private var confirmationActionTitle: String {
        switch viewModel.pendingConfirmation {
        case .clearTranscript:
            return "Borrar"
        case nil:
            return ""
        }
    }
}

#Preview {
    ScribeMainView(viewModel: DictationViewModel())
}
