import SwiftUI

/// Nota de privacidad, siempre visible pero visualmente subordinada al resto de la UI.
struct PrivacyNoteView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "lock.shield")
            Text("Audio y texto se procesan localmente.")
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
