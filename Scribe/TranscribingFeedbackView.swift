import SwiftUI

/// Feedback visual mientras se transcribe. WhisperKit no expone progreso incremental para
/// este flujo, así que se usa un spinner indeterminado en vez de una barra de progreso real.
struct TranscribingFeedbackView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: ScribeSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Transcribiendo localmente")

            Button("Cancelar", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Descarta el resultado cuando llegue; no detiene la inferencia al instante")
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    TranscribingFeedbackView(onCancel: {})
        .padding()
}
