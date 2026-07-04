import AVFoundation

enum MicrophonePermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Consulta y solicita el permiso de micrófono del sistema.
enum MicrophonePermissionManager {
    static func currentStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
