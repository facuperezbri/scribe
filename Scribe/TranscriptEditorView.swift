import SwiftUI

/// Editor de la última transcripción local. Sin historial: un solo texto editable persistido en
/// disco, con una superficie de lectura cómoda — no un `TextEditor` acotado y técnico.
struct TranscriptEditorView: View {
    @Binding var text: String
    var height: CGFloat = 260

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScribeSpacing.xs) {
            TextEditor(text: $text)
                .font(ScribeTypography.transcript)
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(ScribeSpacing.lg)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .scribeControlSurface()
                .accessibilityLabel("Última transcripción")
                .accessibilityHint(text.isEmpty ? "Tu última transcripción aparecerá acá. Mantené Fn para hablar." : "")

            Text(metadataSummary)
                .font(ScribeTypography.metadata)
                .foregroundStyle(ScribeColors.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(metadataSummary)
        }
    }

    private var metadataSummary: String {
        "\(wordCount) palabras · \(text.count) caracteres"
    }
}
