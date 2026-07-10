import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: DictationViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 14) {
            ScribeHeaderView()

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

            TranscriptEditorView(text: $viewModel.transcript)

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

            VStack(spacing: 6) {
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
        .padding(18)
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
        case .replaceTranscript:
            return "Ya tenés una transcripción. Si grabás de nuevo, se va a reemplazar. ¿Querés continuar?"
        case .clearTranscript:
            return "Se va a borrar la transcripción actual. Esta acción no se puede deshacer."
        case nil:
            return ""
        }
    }

    private var confirmationActionTitle: String {
        switch viewModel.pendingConfirmation {
        case .replaceTranscript:
            return "Grabar de nuevo"
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
