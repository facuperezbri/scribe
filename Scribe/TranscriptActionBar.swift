import SwiftUI

/// Acciones manuales sobre la última transcripción: copiar y limpiar. Vive en el encabezado
/// de la tarjeta, no como una fila de botones grandes debajo del texto.
struct TranscriptActionBar: View {
    let isEmpty: Bool
    let isBusy: Bool
    let showCopiedFeedback: Bool
    let onCopy: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: ScribeSpacing.sm) {
            Button(action: onCopy) {
                Label(
                    showCopiedFeedback ? "Copiado" : "Copiar",
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isEmpty)
            .accessibilityLabel(showCopiedFeedback ? "Copiado al portapapeles" : "Copiar transcripción")

            Button(action: onClear) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isEmpty || isBusy)
            .accessibilityLabel("Limpiar transcripción")
            .accessibilityHint(isEmpty ? "" : "Se pedirá confirmación antes de borrar")
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        TranscriptActionBar(
            isEmpty: false,
            isBusy: false,
            showCopiedFeedback: false,
            onCopy: {},
            onClear: {}
        )
        TranscriptActionBar(
            isEmpty: true,
            isBusy: false,
            showCopiedFeedback: false,
            onCopy: {},
            onClear: {}
        )
    }
    .padding()
}
