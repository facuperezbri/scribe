import SwiftUI

/// Encabezado fijo de la ventana compacta: una única línea chica de marca, sin estado dinámico
/// (el estado en vivo vive en `DictationStatusView`, no acá). Reducido a tamaño de nota al pie:
/// el nombre de la app no necesita competir en tamaño con el título de estado central, que es la
/// única cosa que debería saltar a la vista.
struct ScribeHeaderView: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor)
            Text("Scribe")
                .fontWeight(.semibold)
            Text("· Dictado local")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

#Preview {
    ScribeHeaderView()
        .padding()
}
