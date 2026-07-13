import AppKit
import ApplicationServices
import CoreGraphics
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
/// `captureTarget()` lee la app frontmost vía `frontmostApplicationProvider` (por defecto,
/// `NSWorkspace.shared.frontmostApplication`) y descarta a Scribe misma comparando contra
/// `ownBundleIdentifier`.
///
/// `paste(text:target:)` escribe el texto en el portapapeles, reactiva el destino solo si ya no es
/// la app frontmost, y sintetiza ⌘V con `CGEvent`. Todos los efectos de sistema (permiso de
/// Accesibilidad, campo seguro, portapapeles, reactivación, evento de teclado) están detrás de
/// parámetros inyectables — no por flexibilidad especulativa, sino porque ninguno de ellos se puede
/// controlar ni se debe disparar de verdad desde un test unitario (el mismo motivo por el que
/// `HotkeyModifierTrigger`/`frontmostApplicationProvider` ya son inyectables en este archivo).
///
/// Restaura el contenido previo del portapapeles después de pegar (Fase 5), salvo que algo más
/// lo haya escrito en el ínterin (típicamente, el usuario copiando algo nuevo mientras Scribe
/// esperaba para restaurar) — en ese caso no toca nada, para no pisar esa copia más reciente. No
/// tiene una preferencia para deshabilitarse todavía (Fase 6): esta clase solo intenta pegar, sin
/// decidir si corresponde hacerlo más allá de sus propias validaciones (texto vacío, permiso,
/// destino vivo, campo seguro).
final class LiveAutoPasteService: AutoPasteServicing {
    /// Cuánto esperar tras reactivar el destino antes de sintetizar ⌘V. `NSRunningApplication.activate()`
    /// no es sincrónico: la activación real se completa en vueltas de run loop posteriores, así que
    /// sin este margen el evento de teclado puede llegar antes de que el destino sea la app activa.
    /// Heurística fija, no medida en variedad de hardware/apps real — ver checklist de QA manual.
    /// Solo se aplica cuando el destino no es ya la app frontmost (caso común de background-first:
    /// el destino nunca perdió el foco durante la transcripción).
    private static let reactivationDelay: Duration = .milliseconds(120)
    /// Cuánto esperar después de sintetizar ⌘V antes de restaurar el portapapeles anterior. Le da
    /// tiempo al destino a leer el portapapeles (algunos toolkits lo hacen de forma asíncrona) antes
    /// de que Scribe lo pise con el contenido previo. Misma naturaleza heurística que
    /// `reactivationDelay` — ver checklist de QA manual.
    private static let clipboardRestoreDelay: Duration = .milliseconds(200)
    /// `kVK_ANSI_V`, sin importar `Carbon.HIToolbox` solo por esta constante.
    private static let pasteKeyCode: CGKeyCode = 9

    private let frontmostApplicationProvider: () -> NSRunningApplication?
    private let ownBundleIdentifier: String?
    private let isAccessibilityPermissionGranted: () -> Bool
    private let isFocusedElementSecure: () -> Bool
    private let readPasteboardString: () -> String?
    private let writeToPasteboard: (String) -> Bool
    private let pasteboardChangeCount: () -> Int
    private let restorePasteboardString: (String?) -> Void
    private let activateTarget: (NSRunningApplication) -> Void
    private let postPasteKeystroke: () -> Bool
    private let focusedTextNeedsLeadingSpace: () -> Bool
    /// Destino del último auto-paste que efectivamente llegó a pegarse (`.pasted`), para saber si
    /// el próximo dictado continúa sobre el mismo campo — ver comentario en `paste(text:target:)`.
    private var lastPastedTarget: AutoPasteTarget?

    init(
        frontmostApplicationProvider: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isAccessibilityPermissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        isFocusedElementSecure: @escaping () -> Bool = LiveAutoPasteService.systemFocusedElementIsSecure,
        readPasteboardString: @escaping () -> String? = LiveAutoPasteService.readGeneralPasteboardString,
        writeToPasteboard: @escaping (String) -> Bool = LiveAutoPasteService.writeStringToGeneralPasteboard,
        pasteboardChangeCount: @escaping () -> Int = LiveAutoPasteService.generalPasteboardChangeCount,
        restorePasteboardString: @escaping (String?) -> Void = LiveAutoPasteService.restoreGeneralPasteboardString,
        activateTarget: @escaping (NSRunningApplication) -> Void = { $0.activate() },
        postPasteKeystroke: @escaping () -> Bool = LiveAutoPasteService.postCommandVKeystroke,
        focusedTextNeedsLeadingSpace: @escaping () -> Bool = LiveAutoPasteService.systemFocusedElementNeedsLeadingSpace
    ) {
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.ownBundleIdentifier = ownBundleIdentifier
        self.isAccessibilityPermissionGranted = isAccessibilityPermissionGranted
        self.isFocusedElementSecure = isFocusedElementSecure
        self.readPasteboardString = readPasteboardString
        self.writeToPasteboard = writeToPasteboard
        self.pasteboardChangeCount = pasteboardChangeCount
        self.restorePasteboardString = restorePasteboardString
        self.activateTarget = activateTarget
        self.postPasteKeystroke = postPasteKeystroke
        self.focusedTextNeedsLeadingSpace = focusedTextNeedsLeadingSpace
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
        guard !text.isEmpty else { return .emptyText }
        guard isAccessibilityPermissionGranted() else { return .accessibilityPermissionMissing }
        guard !target.runningApplication.isTerminated else { return .targetUnavailable }
        guard !isFocusedElementSecure() else { return .secureField }

        // Cada transcripción llega recortada de espacios (ver `TranscriptionService`), así que dos
        // dictados consecutivos sobre el mismo campo (p. ej. terminar una oración, grabar de nuevo
        // y seguir) se pegarían pegados sin espacio entre medio. La señal principal es
        // `lastPastedTarget`: si el último auto-paste que efectivamente llegó a pegarse fue sobre
        // este mismo destino, este pegado es casi con certeza una continuación del anterior, sin
        // importar qué tan bien (o mal) ese destino exponga su texto/cursor por Accesibilidad — a
        // diferencia de `focusedTextNeedsLeadingSpace()`, que en la práctica falla en varios
        // toolkits (vistas de texto basadas en web/Electron no exponen `AXValue`/
        // `AXSelectedTextRange` de forma confiable) y por eso se mantiene solo como señal
        // adicional, no principal. Se agrega ese espacio acá, no en `transcript`: la transcripción
        // que se ve en la ventana y se copia a mano debe quedar intacta.
        let isContinuingSameTarget = lastPastedTarget == target
        let textToPaste = (isContinuingSameTarget || focusedTextNeedsLeadingSpace()) ? " " + text : text

        let previousClipboardText = readPasteboardString()
        guard writeToPasteboard(textToPaste) else {
            // `writeToPasteboard` limpia el portapapeles antes de escribir (ver
            // `writeStringToGeneralPasteboard`), así que incluso si falla puede haber pisado el
            // contenido anterior — se restaura de una, sin esperar ni chequear `changeCount`: no
            // hubo ningún punto async entre la lectura y este momento donde el usuario pudiera
            // haber copiado algo nuevo.
            restorePasteboardString(previousClipboardText)
            return .pasteboardFailed
        }
        let changeCountAfterOurWrite = pasteboardChangeCount()

        if frontmostApplicationProvider()?.processIdentifier != target.processIdentifier {
            activateTarget(target.runningApplication)
            try? await Task.sleep(for: Self.reactivationDelay)
        }

        let result: AutoPasteResult = postPasteKeystroke() ? .pasted : .eventPostFailed
        if result == .pasted {
            lastPastedTarget = target
        }

        try? await Task.sleep(for: Self.clipboardRestoreDelay)
        if pasteboardChangeCount() == changeCountAfterOurWrite {
            restorePasteboardString(previousClipboardText)
        }
        // Si el `changeCount` cambió, algo más escribió en el portapapeles mientras Scribe
        // esperaba (lo más probable: el usuario copió algo nuevo) — se deja esa copia más
        // reciente en paz en vez de pisarla con el contenido de antes del auto-paste.

        return result
    }

    /// Mejor esfuerzo, no garantizado: pregunta por el rol del elemento con foco vía la API de
    /// Accesibilidad a nivel de sistema. Algunos toolkits (Electron y similares) no exponen
    /// subrole, así que un campo seguro ahí no se detecta — se documenta como limitación conocida
    /// en vez de intentar cubrir cada toolkit puntualmente.
    private static func systemFocusedElementIsSecure() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = focused else {
            return false
        }
        var subrole: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSubroleAttribute as CFString, &subrole) == .success,
              let subroleString = subrole as? String else {
            return false
        }
        return subroleString == kAXSecureTextFieldSubrole as String
    }

    /// Mejor esfuerzo, no garantizado: mira, vía Accesibilidad a nivel de sistema, qué carácter hay
    /// justo antes del cursor en el campo con foco. Si ese carácter no es un espacio en blanco (o
    /// el cursor está al principio del campo, o el campo no expone su valor/selección por AX —
    /// mismo tipo de limitación de toolkit que `systemFocusedElementIsSecure`), no hace falta
    /// agregar nada. El caso que sí importa: el cursor quedó justo después de una palabra (p. ej.
    /// tras un auto-paste anterior) y una nueva transcripción se pegaría pegada a esa palabra sin
    /// espacio de separación.
    private static func systemFocusedElementNeedsLeadingSpace() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = focused else {
            return false
        }
        let element = focusedElement as! AXUIElement

        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else {
            return false
        }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location > 0 else {
            return false
        }

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else {
            return false
        }
        let text16 = text as NSString
        guard range.location <= text16.length else { return false }
        let previousCharacter = text16.substring(with: NSRange(location: range.location - 1, length: 1))
        return previousCharacter.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    private static func readGeneralPasteboardString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    private static func writeStringToGeneralPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private static func generalPasteboardChangeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    /// Restaura `text` en el portapapeles general, o lo deja vacío si `text` es `nil` (no había
    /// nada de texto plano antes del auto-paste). Contenido no textual que hubiera estado antes
    /// (una imagen, un archivo) no se preserva — límite conocido, documentado igual que el de
    /// detección de campos seguros más abajo.
    private static func restoreGeneralPasteboardString(_ text: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let text {
            _ = pasteboard.setString(text, forType: .string)
        }
    }

    /// Sintetiza ⌘V con `CGEvent`, igual que lo haría un teclado real — mismo mecanismo que un
    /// "Copiar" + ⌘V manual, solo que disparado por código.
    private static func postCommandVKeystroke() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }
}
