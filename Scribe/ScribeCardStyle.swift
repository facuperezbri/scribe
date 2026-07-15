import SwiftUI

// MARK: - Card surfaces

/// Tarjeta primaria: superficie elevada, radio grande y una única sombra discreta.
/// En modo oscuro la separación se apoya más en el tono de la superficie que en la sombra.
struct ScribeCardStyle: ViewModifier {
    var padding: CGFloat = ScribeSpacing.xl

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: ScribeRadius.card, style: .continuous)
                    .fill(ScribeColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ScribeRadius.card, style: .continuous)
                    .stroke(ScribeColors.border, lineWidth: 1)
            )
            .shadow(color: ScribeColors.cardShadow, radius: 10, y: 3)
    }
}

/// Superficie silenciosa para el módulo de estado del sistema: más plana que las tarjetas
/// primarias, sin competir por atención.
struct ScribeQuietSurfaceStyle: ViewModifier {
    var padding: CGFloat = ScribeSpacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: ScribeRadius.cardQuiet, style: .continuous)
                    .fill(ScribeColors.surfaceQuiet)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ScribeRadius.cardQuiet, style: .continuous)
                    .stroke(ScribeColors.border, lineWidth: 1)
            )
    }
}

/// Superficie para controles editables dentro de una tarjeta (editor de transcripción).
struct ScribeControlSurfaceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ScribeColors.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: ScribeRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScribeRadius.control, style: .continuous)
                    .stroke(ScribeColors.borderStrong, lineWidth: 1)
            )
    }
}

extension View {
    func scribeCard(padding: CGFloat = ScribeSpacing.xl) -> some View {
        modifier(ScribeCardStyle(padding: padding))
    }

    func scribeQuietSurface(padding: CGFloat = ScribeSpacing.lg) -> some View {
        modifier(ScribeQuietSurfaceStyle(padding: padding))
    }

    func scribeControlSurface() -> some View {
        modifier(ScribeControlSurfaceStyle())
    }
}
