import SwiftUI

/// Feedback visual mientras se transcribe. WhisperKit no expone progreso incremental para
/// este flujo, así que se usa un spinner indeterminado en vez de una barra de progreso real.
struct TranscribingFeedbackView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Button("Cancelar", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

#Preview {
    TranscribingFeedbackView(onCancel: {})
        .padding()
}
