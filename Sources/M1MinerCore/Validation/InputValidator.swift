import Foundation

/// Valide les entrées pour le client Stratum
public enum InputValidator {
    // Longueurs maximales pour les champs
    private static let maxWorkerNameLength = 64
    private static let maxPasswordLength = 128
    private static let maxJobIdLength = 128
    private static let maxExtraNonceLength = 64
    private static let maxNTimeLength = 8
    private static let maxNonceLength = 8
    
    /// Valide un nom de worker
    public static func validateWorkerName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyWorkerName
        }
        
        guard trimmed.count <= maxWorkerNameLength else {
            throw ValidationError.workerNameTooLong(maxLength: maxWorkerNameLength)
        }
        
        // Vérifier les caractères valides (alphanumériques et certains caractères spéciaux)
        let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard trimmed.unicodeScalars.allSatisfy({ allowedChars.contains($0) }) else {
            throw ValidationError.invalidWorkerNameCharacters
        }
        
        return trimmed
    }
    
    /// Valide un mot de passe
    public static func validatePassword(_ password: String) throws -> String {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count <= maxPasswordLength else {
            throw ValidationError.passwordTooLong(maxLength: maxPasswordLength)
        }
        
        return trimmed
    }
    
    /// Valide un ID de job
    public static func validateJobId(_ jobId: String) throws -> String {
        let trimmed = jobId.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyJobId
        }
        
        guard trimmed.count <= maxJobIdLength else {
            throw ValidationError.jobIdTooLong(maxLength: maxJobIdLength)
        }
        
        return trimmed
    }
    
    /// Valide un extra nonce
    public static func validateExtraNonce(_ nonce: String) throws -> String {
        let trimmed = nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyExtraNonce
        }
        
        guard trimmed.count <= maxExtraNonceLength else {
            throw ValidationError.extraNonceTooLong(maxLength: maxExtraNonceLength)
        }
        
        // Vérifier que c'est une chaîne hexadécimale valide
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw ValidationError.invalidHexString
        }
        
        return trimmed
    }
    
    /// Valide un ntime
    public static func validateNTime(_ ntime: String) throws -> String {
        let trimmed = ntime.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count == maxNTimeLength else {
            throw ValidationError.invalidNTimeLength(expectedLength: maxNTimeLength)
        }
        
        // Vérifier que c'est une chaîne hexadécimale valide
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw ValidationError.invalidHexString
        }
        
        return trimmed
    }
    
    /// Valide un nonce
    public static func validateNonce(_ nonce: String) throws -> String {
        let trimmed = nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.count == maxNonceLength else {
            throw ValidationError.invalidNonceLength(expectedLength: maxNonceLength)
        }
        
        // Vérifier que c'est une chaîne hexadécimale valide
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdefABCDEF").inverted) == nil else {
            throw ValidationError.invalidHexString
        }
        
        return trimmed
    }
    
    // MARK: - Erreurs de validation
    
    public enum ValidationError: LocalizedError, Equatable {
        case emptyWorkerName
        case workerNameTooLong(maxLength: Int)
        case invalidWorkerNameCharacters
        case passwordTooLong(maxLength: Int)
        case emptyJobId
        case jobIdTooLong(maxLength: Int)
        case emptyExtraNonce
        case extraNonceTooLong(maxLength: Int)
        case invalidHexString
        case invalidNTimeLength(expectedLength: Int)
        case invalidNonceLength(expectedLength: Int)
        
        public var errorDescription: String? {
            switch self {
            case .emptyWorkerName:
                return "Le nom du worker ne peut pas être vide"
            case .workerNameTooLong(let maxLength):
                return "Le nom du worker ne peut pas dépasser \(maxLength) caractères"
            case .invalidWorkerNameCharacters:
                return "Le nom du worker contient des caractères non autorisés"
            case .passwordTooLong(let maxLength):
                return "Le mot de passe ne peut pas dépasser \(maxLength) caractères"
            case .emptyJobId:
                return "L'ID du job ne peut pas être vide"
            case .jobIdTooLong(let maxLength):
                return "L'ID du job ne peut pas dépasser \(maxLength) caractères"
            case .emptyExtraNonce:
                return "L'extra nonce ne peut pas être vide"
            case .extraNonceTooLong(let maxLength):
                return "L'extra nonce ne peut pas dépasser \(maxLength) caractères"
            case .invalidHexString:
                return "La chaîne doit être une valeur hexadécimale valide"
            case .invalidNTimeLength(let expectedLength):
                return "Le ntime doit faire exactement \(expectedLength) caractères"
            case .invalidNonceLength(let expectedLength):
                return "Le nonce doit faire exactement \(expectedLength) caractères"
            }
        }
    }
}
