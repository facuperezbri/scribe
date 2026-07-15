import AppKit
import ApplicationServices
import Foundation

/// Deriva el estado de permiso de micrófono y las acciones de Ajustes del Sistema asociadas,
/// separado de `DictationViewModel` para que ese mapeo no compita con el resto del flujo de
/// grabar/transcribir. No sabe nada de `AppState`/`DictationSessionState`: solo expone el permiso
/// tal cual lo reporta el sistema, y deja que quien llama decida qué hacer con él.
struct PermissionStatusController {
    static let restrictedMicrophoneError = AppError(
        category: .microphonePermission,
        message: "El acceso al micrófono está restringido en este equipo (gestión parental o de la organización). No se puede habilitar desde la app."
    )

    private let microphonePermissionManager: MicrophonePermissionManaging
    private let isAccessibilityPermissionGranted: () -> Bool

    init(
        microphonePermissionManager: MicrophonePermissionManaging,
        isAccessibilityPermissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.microphonePermissionManager = microphonePermissionManager
        self.isAccessibilityPermissionGranted = isAccessibilityPermissionGranted
    }

    var currentStatus: MicrophonePermissionStatus {
        microphonePermissionManager.currentStatus()
    }

    var accessibilityGranted: Bool {
        isAccessibilityPermissionGranted()
    }

    func requestAccess() async -> Bool {
        await microphonePermissionManager.requestAccess()
    }

    func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilityPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
