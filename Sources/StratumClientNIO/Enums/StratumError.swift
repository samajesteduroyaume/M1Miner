import Foundation

/// Énumération des erreurs possibles du client Stratum
public enum StratumError: Error, LocalizedError, Equatable {
    // Erreurs de connexion
    case notConnected
    case connectionFailed(Error)
    case connectionError(String)
    case connectionTimeout
    case requestTimeout
    case timeout
    case alreadyConnecting
    
    // Erreurs de requête/réponse
    case invalidRequest(String? = nil)
    case invalidResponse(String)
    case unexpectedResponse(String)
    case invalidParameters(String)
    case decodingError(String, Error)
    
    // Erreurs d'authentification
    case authenticationFailed(String)
    case unauthorized(String)
    
    // Erreurs de minage
    case subscriptionFailed(String)
    case invalidJob
    case invalidJobId
    case noActiveJob
    case invalidShare(String)
    case duplicateShare
    case lowDifficultyShare
    case unauthorizedWorker
    case notSubscribed
    
    // Erreurs réseau
    case networkError(Error)
    case serverError(code: Int, message: String)
    
    // Autres erreurs
    case submissionFailed(Error?)
    case submissionRejected(String)
    case unknownError(String)
    
    public var errorDescription: String? {
        switch self {
        // Erreurs de connexion
        case .notConnected:
            return "Non connecté au serveur"
        case .connectionFailed(let error):
            return "Échec de la connexion: \(error.localizedDescription)"
        case .connectionError(let message):
            return "Erreur de connexion: \(message)"
        case .connectionTimeout:
            return "Délai de connexion dépassé"
        case .requestTimeout:
            return "Délai d'attente de la requête dépassé"
        case .timeout:
            return "Délai d'attente dépassé"
        case .alreadyConnecting:
            return "Une connexion est déjà en cours"
            
        // Erreurs de requête/réponse
        case .invalidRequest(let message):
            if let message = message, !message.isEmpty {
                return "Requête invalide: \(message)"
            } else {
                return "Requête invalide"
            }
        case .invalidResponse(let message):
            return "Réponse invalide: \(message)"
        case .unexpectedResponse(let message):
            return "Réponse inattendue: \(message)"
        case .invalidParameters(let message):
            return "Paramètres invalides: \(message)"
        case .decodingError(let message, let error):
            return "Erreur de décodage \(message): \(error.localizedDescription)"
            
        // Erreurs d'authentification
        case .authenticationFailed(let message):
            return "Échec de l'authentification: \(message)"
        case .unauthorized(let message):
            return "Non autorisé: \(message)"
            
        // Erreurs de minage
        case .subscriptionFailed(let message):
            return "Échec de l'abonnement: \(message)"
        case .invalidJob:
            return "Travail invalide"
        case .invalidJobId:
            return "ID de travail invalide"
        case .noActiveJob:
            return "Aucun travail actif"
        case .invalidShare(let message):
            return "Partage invalide: \(message)"
        case .duplicateShare:
            return "Partage en double"
        case .lowDifficultyShare:
            return "Difficulté de partage trop faible"
        case .unauthorizedWorker:
            return "Travailleur non autorisé"
        case .notSubscribed:
            return "Non abonné au serveur"
            
        // Erreurs réseau
        case .networkError(let error):
            return "Erreur réseau: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Erreur serveur (\(code)): \(message)"
            
        // Autres erreurs
        case .submissionFailed(let error?):
            return "Échec de la soumission: \(error.localizedDescription)"
        case .submissionFailed(nil):
            return "Échec inconnu de la soumission"
        case .submissionRejected(let reason):
            return "Soumission rejetée: \(reason)"
        case .unknownError(let message):
            return "Erreur inconnue: \(message)"
        }
    }
    
    // Implémentation de Equatable
    public static func == (lhs: StratumError, rhs: StratumError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected),
             (.connectionTimeout, .connectionTimeout),
             (.requestTimeout, .requestTimeout),
             (.invalidRequest, .invalidRequest),
             (.invalidJob, .invalidJob),
             (.invalidJobId, .invalidJobId),
             (.noActiveJob, .noActiveJob),
             (.duplicateShare, .duplicateShare),
             (.lowDifficultyShare, .lowDifficultyShare),
             (.unauthorizedWorker, .unauthorizedWorker),
             (.notSubscribed, .notSubscribed):
            return true
            
        case (.connectionError(let lhsMsg), .connectionError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.invalidResponse(let lhsMsg), .invalidResponse(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.unexpectedResponse(let lhsMsg), .unexpectedResponse(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.invalidParameters(let lhsMsg), .invalidParameters(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.authenticationFailed(let lhsMsg), .authenticationFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.unauthorized(let lhsMsg), .unauthorized(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.subscriptionFailed(let lhsMsg), .subscriptionFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.invalidShare(let lhsMsg), .invalidShare(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.serverError(let lhsCode, let lhsMsg), .serverError(let rhsCode, let rhsMsg)):
            return lhsCode == rhsCode && lhsMsg == rhsMsg
        case (.submissionRejected(let lhsReason), .submissionRejected(let rhsReason)):
            return lhsReason == rhsReason
        case (.unknownError(let lhsMsg), .unknownError(let rhsMsg)):
            return lhsMsg == rhsMsg
            
        // Pour les erreurs avec Error, on ne peut pas les comparer directement
        case (.connectionFailed, .connectionFailed),
             (.decodingError, .decodingError),
             (.networkError, .networkError),
             (.submissionFailed, .submissionFailed):
            return false
            
        default:
            return false
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .alreadyConnecting:
            return "Une connexion est déjà en cours. Attendez que la connexion actuelle soit établie ou annulée."
        case .notConnected:
            return "Assurez-vous que le serveur est en ligne et que vous êtes connecté à Internet."
        case .connectionFailed:
            return "Vérifiez votre connexion Internet et réessayez."
        case .connectionError:
            return "Vérifiez l'URL du serveur et réessayez."
        case .connectionTimeout, .requestTimeout, .timeout:
            return "Le délai de la requête a expiré. Vérifiez votre connexion et réessayez."
        case .invalidRequest, .invalidResponse, .unexpectedResponse, .decodingError, .invalidParameters:
            return "Veuillez réessayer plus tard. Si le problème persiste, contactez le support."
        case .authenticationFailed, .unauthorized:
            return "Vérifiez vos identifiants et réessayez."
        case .subscriptionFailed, .notSubscribed:
            return "Impossible de s'abonner au serveur. Vérifiez les paramètres et réessayez."
        case .invalidJob, .invalidJobId, .noActiveJob, .invalidShare, .duplicateShare, .lowDifficultyShare, .unauthorizedWorker:
            return "Le travail de minage est invalide. Le mineur va automatiquement demander un nouveau travail."
        case .serverError:
            return "Le serveur a rencontré une erreur. Réessayez plus tard."
        case .networkError:
            return "Erreur réseau. Vérifiez votre connexion Internet et réessayez."
        case .submissionFailed, .submissionRejected:
            return "Échec de la soumission du travail. Vérifiez les paramètres et réessayez."
        case .unknownError:
            return "Une erreur inattendue s'est produite. Veuillez réessayer."
        }
    }
}
