import AppKit
import Foundation
import FoundationModels

/// Motivo por el que el modelo on-device de Apple Intelligence no está disponible para
/// reformatear el transcripto. `.other` cubre motivos futuros que Apple pueda agregar a
/// `SystemLanguageModel.Availability.UnavailableReason` sin romper este switch.
enum AppleIntelligenceUnavailableReason: Equatable {
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case other

    var message: String {
        switch self {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence no está activado en este equipo."
        case .deviceNotEligible:
            return "Este equipo no soporta Apple Intelligence."
        case .modelNotReady:
            return "El modelo de Apple Intelligence todavía no está listo. Probá de nuevo en un momento."
        case .other:
            return "Apple Intelligence no está disponible en este momento."
        }
    }
}

/// Deriva la disponibilidad del modelo on-device de Apple Intelligence (Foundation Models),
/// separado de `DictationViewModel` igual que `PermissionStatusController` separa el permiso de
/// micrófono. Chequeo en vivo sin estado propio: `SystemLanguageModel.default.availability` ya
/// refleja el estado real del sistema en cada consulta, así que no hace falta cachear ni
/// persistir nada acá.
struct AppleIntelligenceAvailabilityController {
    // El closure devuelve `AppleIntelligenceUnavailableReason?` (no el enum de `FoundationModels`
    // directamente) para que los tests puedan inyectar un resultado sin importar `FoundationModels`
    // ni construir `SystemLanguageModel.Availability` — mismo criterio que el `Bool` plano que
    // inyecta `PermissionStatusController` para el permiso de Accesibilidad.
    private let unavailableReasonProvider: () -> AppleIntelligenceUnavailableReason?

    init(unavailableReasonProvider: @escaping () -> AppleIntelligenceUnavailableReason? = Self.systemUnavailableReason) {
        self.unavailableReasonProvider = unavailableReasonProvider
    }

    var unavailableReason: AppleIntelligenceUnavailableReason? {
        unavailableReasonProvider()
    }

    var isAvailable: Bool {
        unavailableReason == nil
    }

    private static func systemUnavailableReason() -> AppleIntelligenceUnavailableReason? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .other
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"), NSWorkspace.shared.open(url) {
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
