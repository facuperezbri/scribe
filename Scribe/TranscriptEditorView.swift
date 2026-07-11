import SwiftUI

/// Área editable donde aparece la transcripción, con presentación tipo panel nativo.
struct TranscriptEditorView: View {
    @Binding var text: String

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcripción")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            // El placeholder y el TextEditor comparten el mismo `.padding(10)`: al aplicarse
            // sobre un Group, SwiftUI lo reparte igual a cada hijo, así quedan alineados
            // sin duplicar el número en dos lugares distintos. El placeholder suma un leading
            // extra porque NSTextView (detrás de TextEditor) tiene su propio inset horizontal
            // interno que el Text plano no hereda.
            ZStack(alignment: .topLeading) {
                Group {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)

                    if text.isEmpty {
                        Text("Tu transcripción aparecerá acá...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlCornerRadius)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )

            Text("\(wordCount) palabras · \(text.count) caracteres")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
