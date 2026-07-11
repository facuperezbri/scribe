import AppKit
import SwiftUI

/// Ícono original de Scribe (Fase 4): barras de ecualizador abstractas flanqueando una cápsula
/// central tipo micrófono, sobre un degradé propio. No reutiliza ni deriva assets de Wispr Flow
/// ni de ninguna otra app — es geometría simple generada acá mismo, pensada para leer bien a
/// tamaño chico (16-32pt) en el Dock/Finder.
private struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.14, blue: 0.36),
                            Color(red: 0.16, green: 0.52, blue: 0.60)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 26) {
                bar(height: 210, opacity: 0.5)
                bar(height: 330, opacity: 0.75)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 132, height: 460)
                bar(height: 330, opacity: 0.75)
                bar(height: 210, opacity: 0.5)
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private func bar(height: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: 86, height: height)
    }
}

@MainActor
private func renderAndWrite() throws {
    let renderer = ImageRenderer(content: AppIconArtwork())
    renderer.scale = 1.0

    guard let cgImage = renderer.cgImage else {
        FileHandle.standardError.write("No se pudo renderizar el ícono.\n".data(using: .utf8)!)
        exit(1)
    }

    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("No se pudo codificar el PNG.\n".data(using: .utf8)!)
        exit(1)
    }

    let outputPath = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "scribe-icon-master.png"
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Ícono maestro escrito en \(outputPath)")
}

try await MainActor.run { try renderAndWrite() }
