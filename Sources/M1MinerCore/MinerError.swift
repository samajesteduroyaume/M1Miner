import Foundation

/// Erreurs spécifiques au mineur
public enum MinerError: Error, LocalizedError {
    case metalNotSupported
    case metalDeviceNotFound
    case metalNotInitialized
    case metalLibraryError(String)
    case metalPipelineError(String)
    case invalidPoolURL
    case stratumError(String)
    case invalidJob
    case invalidShare
    case invalidConfiguration
    case bufferCreationFailed
    case commandCreationFailed
    case unknownError
    
    public var errorDescription: String? {
        switch self {
        case .metalNotSupported:
            return "Metal n'est pas supporté sur cet appareil"
        case .metalDeviceNotFound:
            return "Aucun périphérique Metal trouvé"
        case .metalLibraryError(let message):
            return "Erreur de bibliothèque Metal: \(message)"
        case .metalPipelineError(let message):
            return "Erreur de pipeline Metal: \(message)"
        case .invalidPoolURL:
            return "URL du pool invalide"
        case .stratumError(let message):
            return "Erreur Stratum: \(message)"
        case .invalidJob:
            return "Travail de minage invalide"
        case .invalidShare:
            return "Partage invalide"
        case .invalidConfiguration:
            return "Configuration du mineur invalide"
        case .metalNotInitialized:
            return "Metal n'est pas correctement initialisé"
        case .bufferCreationFailed:
            return "Échec de la création des tampons GPU"
        case .commandCreationFailed:
            return "Échec de la création des commandes GPU"
        case .unknownError:
            return "Une erreur inconnue est survenue"
        }
    }
}
