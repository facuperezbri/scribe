import SwiftUI

/// Sección honesta de la última transcripción local: editable, con copiar, limpiar y
/// recuperación de un solo reemplazo — no un historial. Es la superficie de lectura
/// dominante cuando hay texto.
struct LastTranscriptCard: View {
    @ObservedObject var viewModel: DictationViewModel

    private var isEmpty: Bool { viewModel.transcript.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.md) {
            header

            if isEmpty {
                TranscriptEmptyState()
            } else {
                TranscriptEditorView(text: $viewModel.transcript)
            }

            if let previous = viewModel.previousTranscript {
                TranscriptRecoveryBanner(onRestore: viewModel.restorePreviousTranscript)
                    .accessibilityHint(previous)
            }
        }
        .scribeCard()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Última transcripción")
                .font(ScribeTypography.sectionTitle)
                .foregroundStyle(ScribeColors.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            TranscriptActionBar(
                isEmpty: isEmpty,
                isBusy: viewModel.isBusy,
                showCopiedFeedback: viewModel.showCopiedFeedback,
                onCopy: viewModel.copyTranscript,
                onClear: viewModel.clearTranscript
            )
        }
    }
}

#Preview("Vacío") {
    LastTranscriptCard(viewModel: DictationViewModel())
        .padding()
        .frame(width: 480)
}

@MainActor
private func makePreviewViewModelWithText() -> DictationViewModel {
    let viewModel = DictationViewModel()
    viewModel.transcript = "Hola, esta es una transcripción de ejemplo guardada localmente."
    return viewModel
}

#Preview("Con texto") {
    LastTranscriptCard(viewModel: makePreviewViewModelWithText())
        .padding()
        .frame(width: 480)
}
