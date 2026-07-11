import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: DictationViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            ScribeHeaderView()

            VStack(spacing: Metrics.cardInnerSpacing) {
                DictationStatusView(
                    primaryState: viewModel.primaryState,
                    title: viewModel.primaryStateTitle,
                    hint: viewModel.primaryStateHint,
                    elapsed: viewModel.recordingElapsed,
                    inputLevel: viewModel.inputLevel,
                    warningText: viewModel.recordingWarningText,
                    isStrongWarning: viewModel.isStrongRecordingWarning,
                    onCancelTranscribing: viewModel.cancelTranscription,
                    showCopyCallToAction: viewModel.showCopyCallToAction,
                    showCopiedFeedback: viewModel.showCopiedFeedback,
                    onCopy: viewModel.copyTranscript
                )

                RecordingButton(
                    isRecording: viewModel.isRecording,
                    isBusy: viewModel.isBusy,
                    title: viewModel.recordButtonTitle,
                    action: { viewModel.handlePrimaryDictationAction() }
                )

                if viewModel.isMicrophonePermissionDenied {
                    Button("Abrir Ajustes del Sistema", action: viewModel.openMicrophonePrivacySettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .cardBackground()

            VStack(spacing: Metrics.cardInnerSpacing) {
                TranscriptEditorView(text: $viewModel.transcript)

                if viewModel.previousTranscript != nil {
                    Button(action: viewModel.restorePreviousTranscript) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Deshacer reemplazo")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Button(viewModel.showCopiedFeedback ? "Copiado" : "Copiar", action: viewModel.copyTranscript)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.transcript.isEmpty)

                    Button("Limpiar", action: viewModel.clearTranscript)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.transcript.isEmpty || viewModel.isBusy)
                }
            }
            .cardBackground()

            VStack(spacing: Metrics.footerSpacing) {
                ModelStatusView(
                    isInstalled: viewModel.isModelInstalled,
                    modelName: ModelManager.modelDisplayName,
                    sizeDescription: ModelManager.modelSizeDescription,
                    isDownloading: viewModel.isDownloadingModel,
                    downloadProgress: viewModel.downloadProgress,
                    onReveal: viewModel.revealModelInFinder,
                    onDownload: viewModel.downloadModel
                )

                HotkeyStatusView(
                    status: viewModel.hotkeyStatus,
                    onOpenSettings: viewModel.openAccessibilityPrivacySettings,
                    onRefresh: viewModel.refreshHotkeyStatus
                )

                PrivacyNoteView()
            }
        }
        .padding(Metrics.cardPadding)
        .frame(minWidth: 380, minHeight: 460)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.refreshHotkeyStatus()
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
    ContentView(viewModel: DictationViewModel())
}
