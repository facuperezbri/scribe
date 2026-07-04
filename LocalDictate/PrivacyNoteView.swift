import SwiftUI

/// Nota de privacidad, siempre visible pero visualmente subordinada al resto de la UI.
struct PrivacyNoteView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "lock.shield")
            Text("El audio y el texto se procesan localmente en esta Mac. No se envían a servidores. Solo se usa internet para descargar el modelo si todavía no está instalado.")
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
