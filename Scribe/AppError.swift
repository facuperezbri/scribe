import Foundation

/// Categoría de un error de la app, independiente del mensaje mostrado. Permite a los tests
/// razonar sobre qué falló sin comparar el texto (en español) que ve el usuario.
enum AppErrorCategory: Equatable {
    case microphonePermission
    case recording
    case transcription
    case model
    case storage
    case clipboard
    case unknown

    /// Mensaje en español por defecto para la categoría. Único lugar que decide el texto
    /// que ve el usuario ante un error sin un mensaje más específico.
    var defaultMessage: String {
        switch self {
        case .microphonePermission:
            return "No se pudo acceder al micrófono."
        case .recording:
            return "No se pudo grabar el audio."
        case .transcription:
            return "No se pudo transcribir el audio."
        case .model:
            return "No se pudo descargar el modelo de transcripción."
        case .storage:
            return "No se pudo guardar la transcripción."
        case .clipboard:
            return "No se pudo copiar al portapapeles."
        case .unknown:
            return "Ocurrió un error inesperado."
        }
    }
}

/// Error tipado de la app. Envuelve el error subyacente (si lo hay) bajo una categoría fija,
/// para que la UI muestre un mensaje en español consistente y los tests puedan comparar por
/// categoría en vez de por texto.
struct AppError: Error, Equatable {
    let category: AppErrorCategory
    let message: String
    let debugDescription: String?

    init(category: AppErrorCategory, message: String? = nil, underlying: Error? = nil) {
        self.category = category
        self.message = message ?? category.defaultMessage
        self.debugDescription = underlying?.localizedDescription
    }
}
