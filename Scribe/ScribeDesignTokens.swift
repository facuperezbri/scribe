import SwiftUI
import AppKit

// MARK: - Adaptive color helper

private extension Color {
    /// Crea un color adaptable a modo claro/oscuro sin depender de un catálogo de assets.
    static func scribeAdaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
}

// MARK: - Colors

/// Paleta de Scribe: grafito cálido (no negro puro), un acento índigo con moderación,
/// y colores de estado distinguibles entre sí — grabación, advertencia, éxito y error.
enum ScribeColors {
    /// Fondo de ventana: grafito cálido en oscuro, hueso cálido en claro.
    static let windowBackground = Color.scribeAdaptive(
        light: (0.957, 0.949, 0.933),
        dark: (0.098, 0.102, 0.118)
    )

    /// Superficie elevada para tarjetas primarias.
    static let surface = Color.scribeAdaptive(
        light: (0.988, 0.984, 0.973),
        dark: (0.133, 0.137, 0.161)
    )

    /// Superficie más silenciosa para el módulo de estado del sistema.
    static let surfaceQuiet = Color.scribeAdaptive(
        light: (0.973, 0.969, 0.957),
        dark: (0.118, 0.122, 0.141)
    )

    /// Superficie de controles editables (editor de transcripción).
    static let controlSurface = Color.scribeAdaptive(
        light: (0.945, 0.937, 0.922),
        dark: (0.161, 0.165, 0.192)
    )

    /// Texto principal.
    static let ink = Color.scribeAdaptive(
        light: (0.114, 0.110, 0.102),
        dark: (0.957, 0.949, 0.941)
    )

    /// Texto secundario y metadatos.
    static let inkSecondary = Color.scribeAdaptive(
        light: (0.404, 0.388, 0.369),
        dark: (0.706, 0.694, 0.678)
    )

    /// Texto terciario: disclaimers y metadata de baja prioridad. Sigue siendo legible.
    static let inkTertiary = Color.scribeAdaptive(
        light: (0.514, 0.498, 0.478),
        dark: (0.541, 0.529, 0.514)
    )

    /// Acento de marca: índigo eléctrico, reservado para la firma visual, el foco y enlaces.
    static let accent = Color.scribeAdaptive(
        light: (0.400, 0.341, 0.851),
        dark: (0.502, 0.443, 0.961)
    )

    /// Fondo sutil con acento (recuperación, foco).
    static let accentSubtle = accent.opacity(0.14)

    /// Borde hairline para tarjetas y paneles.
    static let border = Color.primary.opacity(0.07)

    /// Borde un poco más visible en campos y controles editables.
    static let borderStrong = Color.primary.opacity(0.12)

    /// Sombra sutil de tarjetas (discreta; en oscuro se apoya más en separación tonal).
    static let cardShadow = Color.black.opacity(0.14)

    // MARK: Estados semánticos — cada uno distinguible por tono, no solo por opacidad.

    /// Grabación activa: coral cálido, distinto del rojo de error.
    static let recording = Color.scribeAdaptive(
        light: (0.839, 0.278, 0.184),
        dark: (1.0, 0.420, 0.341)
    )

    /// Procesamiento/actividad en curso: mismo tono que el acento.
    static let processing = accent

    /// Atención requerida, sin bloquear el uso.
    static let warning = Color.scribeAdaptive(
        light: (0.725, 0.471, 0.169),
        dark: (0.949, 0.718, 0.357)
    )

    /// Local, listo, en buen estado.
    static let success = Color.scribeAdaptive(
        light: (0.122, 0.561, 0.357),
        dark: (0.435, 0.796, 0.608)
    )

    /// Error real (permiso denegado, falla de transcripción) — distinto del coral de grabación.
    static let error = Color.scribeAdaptive(
        light: (0.769, 0.161, 0.353),
        dark: (1.0, 0.329, 0.439)
    )

    // Medidor de audio en ventana principal
    static let meterTrack = Color.primary.opacity(0.12)
    static let meterFill = success

    // Overlay flotante (fondo oscuro fijo por diseño; no cambia con el modo del sistema)
    static let overlayBackground = Color.black.opacity(0.82)
    static let overlayBorder = Color.white.opacity(0.08)
    static let overlayForeground = Color.white
    static let overlayShadow = Color.black.opacity(0.35)
}

// MARK: - Spacing

/// Escala de espaciado en múltiplos de 4pt, con más aire que la escala anterior.
enum ScribeSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40
}

// MARK: - Radius

enum ScribeRadius {
    /// Controles e insets editables.
    static let control: CGFloat = 14
    /// Tarjetas primarias (hero, transcripción).
    static let card: CGFloat = 20
    /// Superficie silenciosa de estado del sistema.
    static let cardQuiet: CGFloat = 16
}

// MARK: - Typography

/// Roles tipográficos del sistema; sin fuentes importadas. Escala más grande y con más
/// separación entre niveles para reforzar jerarquía.
enum ScribeTypography {
    /// Marca "Scribe" en la barra de identidad.
    static let brand = Font.system(size: 19, weight: .semibold)
    /// Título de estado primario — el elemento de mayor autoridad visual de la ventana.
    static let primaryState = Font.system(size: 28, weight: .semibold)
    /// Título de sección (Última transcripción, Sistema).
    static let sectionTitle = Font.system(size: 18, weight: .semibold)
    /// Texto de la transcripción — cómodo para lectura prolongada.
    static let transcript = Font.system(size: 16, weight: .regular)
    /// Texto de ayuda / cuerpo general.
    static let body = Font.system(size: 15, weight: .regular)
    /// Valores de estado y acciones secundarias.
    static let statusValue = Font.system(size: 13, weight: .medium)
    /// Metadata: contadores, disclaimers breves.
    static let metadata = Font.system(size: 12, weight: .regular)
    /// Temporizador de grabación.
    static let monoTimer = Font.system(.body, design: .monospaced)
    /// Etiqueta del overlay flotante.
    static let overlayLabel = Font.system(size: 13, weight: .medium)
}

// MARK: - Motion

enum ScribeMotion {
    static let fast: TimeInterval = 0.15
    static let standard: TimeInterval = 0.25
    static let pulse: TimeInterval = 0.9
    static let meter: TimeInterval = 0.12
    static let transcribingDot: TimeInterval = 0.6
    static let transcribingStagger: TimeInterval = 0.15

    /// Animación de pulso para grabación; respeta Reduce Motion.
    static func recordingPulse(isEnabled: Bool, reduceMotion: Bool) -> Animation {
        guard isEnabled, !reduceMotion else { return .default }
        return .easeInOut(duration: pulse).repeatForever(autoreverses: true)
    }
}

// MARK: - Primary state colors

extension PrimaryState {
    /// Color semántico asociado al estado central de dictado.
    var scribeIconColor: Color {
        switch self {
        case .ready, .transcriptReady:
            return ScribeColors.accent
        case .startingRecording, .requestingPermission, .stoppingRecording, .transcribing, .downloadingModel:
            return ScribeColors.processing
        case .recording:
            return ScribeColors.recording
        case .missingModel, .inputMonitoringRequired:
            return ScribeColors.warning
        case .microphoneDenied, .error:
            return ScribeColors.error
        }
    }
}
