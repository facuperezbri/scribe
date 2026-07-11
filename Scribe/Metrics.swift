import SwiftUI

/// Escala compartida de espaciado y radios (Fase 3 del rediseño estilo Wispr): antes cada vista
/// definía sus propios números sueltos (14, 10, 8, 6, 4...) sin relación entre sí, lo que hacía
/// que la ventana se sintiera un prototipo. Un solo lugar para estos valores evita que vuelvan a
/// divergir.
enum Metrics {
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 16
    static let cardInnerSpacing: CGFloat = 10
    static let footerSpacing: CGFloat = 6
}

/// Fondo con borde y sombra sutil que agrupa una sección de la ventana en una "tarjeta",
/// separándola del fondo plano de la ventana — usado por el área de estado central y por la
/// transcripción, las dos zonas que deben leerse como bloques propios en vez de filas sueltas.
private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Metrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}
