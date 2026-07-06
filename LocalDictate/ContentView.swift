import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DictationViewModel()

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                    Text("LocalDictate")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("Dictado local para prompts e ideas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            StatusBadgeView(text: viewModel.statusText, kind: viewModel.statusKind)

            RecordingButton(
                isRecording: viewModel.isRecording,
                isBusy: viewModel.isBusy,
                title: viewModel.recordButtonTitle,
                action: { viewModel.handlePrimaryDictationAction() }
            )

            if viewModel.isRecording {
                RecordingFeedbackView(
                    elapsed: viewModel.recordingElapsed,
                    inputLevel: viewModel.inputLevel,
                    warningText: viewModel.recordingWarningText,
                    isStrongWarning: viewModel.isStrongRecordingWarning
                )
            }

            if viewModel.isTranscribing {
                TranscribingFeedbackView(onCancel: viewModel.cancelTranscription)
            }

            if viewModel.isMicrophonePermissionDenied {
                Button("Abrir Ajustes del Sistema", action: viewModel.openMicrophonePrivacySettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            TranscriptEditorView(text: $viewModel.transcript)

            HStack(spacing: 12) {
                Button(viewModel.showCopiedFeedback ? "Copiado" : "Copiar", action: viewModel.copyTranscript)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.transcript.isEmpty)

                Button("Limpiar", action: viewModel.clearTranscript)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.transcript.isEmpty || viewModel.isBusy)
            }

            Divider()

            VStack(spacing: 8) {
                ModelStatusView(
                    isInstalled: viewModel.isModelInstalled,
                    modelName: ModelManager.modelDisplayName,
                    sizeDescription: ModelManager.modelSizeDescription,
                    isDownloading: viewModel.isDownloadingModel,
                    downloadProgress: viewModel.downloadProgress,
                    onReveal: viewModel.revealModelInFinder,
                    onDownload: viewModel.downloadModel
                )

                PrivacyNoteView()
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 580)
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
    ContentView()
}
