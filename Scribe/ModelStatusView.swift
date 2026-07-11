import SwiftUI

/// Estado del modelo de transcripción, presentado de forma subordinada al resto de la UI.
struct ModelStatusView: View {
    let isInstalled: Bool
    let modelName: String
    let sizeDescription: String
    let isDownloading: Bool
    let downloadProgress: Double
    let onReveal: () -> Void
    let onDownload: () -> Void

    var body: some View {
        if isInstalled {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("\(modelName) instalado")
                Button("Ver en Finder", action: onReveal)
                    .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if isDownloading {
            VStack(spacing: 4) {
                Text("Descargando \(modelName)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: downloadProgress)
                    .frame(maxWidth: 260)
            }
        } else {
            VStack(spacing: 4) {
                Button("Descargar modelo de transcripción (\(sizeDescription))", action: onDownload)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text("\(modelName) se descarga una sola vez y se ejecuta localmente en esta Mac.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
