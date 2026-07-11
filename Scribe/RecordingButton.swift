import SwiftUI

/// Botón principal de Grabar/Detener, grande y con icono, como acción primaria de la ventana.
struct RecordingButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                Text(title)
            }
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecording ? .red : .accentColor)
        .controlSize(.large)
        .disabled(isBusy)
    }
}
