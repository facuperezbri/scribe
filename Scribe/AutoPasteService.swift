import AppKit
import Foundation

/// App capturada como destino de un auto-paste (la que tenía el foco antes de que arrancara el
/// dictado). Guarda `runningApplication` además de los campos planos porque `LiveAutoPasteService`
/// lo necesita para reactivar esa app más adelante (`NSRunningApplication.activate()`); los campos
/// planos existen para que tests/logging no dependan de inspeccionar ese objeto vivo.
struct AutoPasteTarget: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let runningApplication: NSRunningApplication

    /// Dos capturas son la misma app en ejecución si comparten process id; `runningApplication`
    /// queda afuera de la comparación porque es una referencia viva, no un valor.
    static func == (lhs: AutoPasteTarget, rhs: AutoPasteTarget) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
    }
}

/// Resultado tipado de un intento de auto-paste, en el mismo espíritu que `AppError`: la UI y los
/// tests razonan sobre el caso, no sobre un mensaje de error.
enum AutoPasteResult: Equatable {
    /// El texto se pegó en el destino capturado.
    case pasted
    /// No había ninguna app destino capturada (p. ej. el dictado arrancó desde la propia ventana
    /// de Scribe).
    case noTarget
    /// Había un destino capturado, pero ya no está disponible al momento de pegar (se cerró).
    case targetUnavailable
    /// Falta el permiso de Accesibilidad que requiere sintetizar ⌘V.
    case accessibilityPermissionMissing
    /// El texto a pegar estaba vacío.
    case emptyText
    /// El campo con foco en el destino parece un campo seguro (contraseña); no se intenta pegar.
    case secureField
    /// Falló la escritura/lectura del portapapeles.
    case pasteboardFailed
    /// Falló la síntesis del evento de teclado ⌘V.
    case eventPostFailed
    /// Falla no clasificada.
    case unknown
}

/// Contrato mínimo para pegar la transcripción en la app que tenía el foco antes del dictado. No
/// sabe nada de grabar/transcribir ni de las reglas de negocio de `DictationViewModel`: solo
/// captura un destino y, más tarde, intenta pegar texto en él.
protocol AutoPasteServicing {
    /// Captura la app frontmost actual como destino, o `nil` si no hay ninguna capturable (p. ej.
    /// es la propia Scribe). Se llama de forma sincrónica al arrancar una grabación, antes de que
    /// cualquier activación de ventana pueda cambiar qué app está al frente.
    func captureTarget() -> AutoPasteTarget?
    /// Intenta pegar `text` en `target`. No decide si corresponde intentarlo (texto vacío,
    /// transcripción fallida, etc.) — eso es responsabilidad de quien llama.
    func paste(text: String, target: AutoPasteTarget) async -> AutoPasteResult
}

/// Implementación real de `AutoPasteServicing`.
///
/// `captureTarget()` ya funciona: lee la app frontmost vía `frontmostApplicationProvider` (por
/// defecto, `NSWorkspace.shared.frontmostApplication`) y descarta a Scribe misma comparando contra
/// `ownBundleIdentifier`. Ambos son parámetros inyectables — no por flexibilidad especulativa, sino
/// porque `NSWorkspace.shared` no se puede controlar desde un test unitario, el mismo motivo por el
/// que `HotkeyTrigger` es inyectable en `LiveGlobalHotkeyService`.
///
/// `paste(text:target:)` todavía no pega nada de verdad: el reemplazo de portapapeles + reactivar
/// destino + sintetizar ⌘V es Fase 4. Por ahora devuelve `.unknown` siempre, así que llamarlo no
/// tiene efecto observable.
final class LiveAutoPasteService: AutoPasteServicing {
    private let frontmostApplicationProvider: () -> NSRunningApplication?
    private let ownBundleIdentifier: String?

    init(
        frontmostApplicationProvider: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func captureTarget() -> AutoPasteTarget? {
        guard let frontmost = frontmostApplicationProvider() else { return nil }
        guard frontmost.bundleIdentifier != ownBundleIdentifier else { return nil }
        return AutoPasteTarget(
            processIdentifier: frontmost.processIdentifier,
            bundleIdentifier: frontmost.bundleIdentifier,
            localizedName: frontmost.localizedName,
            runningApplication: frontmost
        )
    }

    func paste(text: String, target: AutoPasteTarget) async -> AutoPasteResult {
        .unknown
    }
}
