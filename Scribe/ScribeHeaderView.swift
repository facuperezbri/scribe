import SwiftUI

/// Encabezado fijo de la ventana compacta: nombre de la app y una única línea de marca,
/// sin estado dinámico (el estado en vivo vive en `DictationStatusView`, no acá).
struct ScribeHeaderView: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                Text("Scribe")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            Text("Dictado local")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScribeHeaderView()
        .padding()
}
