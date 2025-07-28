import Foundation

/// Résultat de la soumission d'un bloc au pool de minage
public struct SubmitResult: Codable, Equatable {
    /// Indique si la soumission a été acceptée
    public let accepted: Bool
    
    /// Message d'erreur éventuel
    public let error: Error?
    
    /// Identifiant du travail
    public let jobId: String
    
    /// Nonce utilisé pour la soumission
    public let nonce: UInt32
    
    /// Difficulté du travail (optionnel)
    public let difficulty: Double?
    
    /// Message détaillé (acceptation/rejet)
    public let message: String?
    
    /// Initialise un nouveau résultat de soumission
    /// - Parameters:
    ///   - accepted: Indique si la soumission a été acceptée
    ///   - error: Erreur éventuelle
    ///   - jobId: Identifiant du travail
    ///   - nonce: Nonce utilisé pour la soumission
    public init(accepted: Bool, error: Error? = nil, jobId: String, nonce: UInt32, difficulty: Double? = nil, message: String? = nil) {
        self.accepted = accepted
        self.error = error
        self.jobId = jobId
        self.nonce = nonce
        self.difficulty = difficulty
        self.message = message
    }
    
    // Implémentation de Equatable
    public static func == (lhs: SubmitResult, rhs: SubmitResult) -> Bool {
        return lhs.accepted == rhs.accepted &&
               lhs.jobId == rhs.jobId &&
               lhs.nonce == rhs.nonce &&
               lhs.difficulty == rhs.difficulty &&
               lhs.message == rhs.message &&
               (lhs.error?.localizedDescription == rhs.error?.localizedDescription)
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case accepted
        case errorMessage
        case jobId
        case nonce
        case difficulty
        case message
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decode(Bool.self, forKey: .accepted)
        jobId = try container.decode(String.self, forKey: .jobId)
        nonce = try container.decode(UInt32.self, forKey: .nonce)
        
        if let errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) {
            error = NSError(domain: "M1Miner", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        } else {
            error = nil
        }
        difficulty = try container.decodeIfPresent(Double.self, forKey: .difficulty)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accepted, forKey: .accepted)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(nonce, forKey: .nonce)
        
        if let error = error as NSError? {
            try container.encode(error.localizedDescription, forKey: .errorMessage)
        }
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

// Extension pour faciliter la création de résultats de soumission
extension SubmitResult {
    /// Crée un résultat de soumission réussi
    /// - Parameters:
    ///   - jobId: Identifiant du travail
    ///   - nonce: Nonce utilisé pour la soumission
    /// - Returns: Un résultat de soumission réussi
    public static func success(jobId: String, nonce: UInt32, difficulty: Double? = nil, message: String? = nil) -> SubmitResult {
        return SubmitResult(
            accepted: true, 
            error: nil, 
            jobId: jobId, 
            nonce: nonce, 
            difficulty: difficulty,
            message: message
        )
    }
    
    /// Crée un résultat de soumission échoué
    /// - Parameters:
    ///   - error: Erreur survenue
    ///   - jobId: Identifiant du travail
    ///   - nonce: Nonce utilisé pour la soumission
    /// - Returns: Un résultat de soumission échoué
    public static func failure(_ error: Error, jobId: String, nonce: UInt32, difficulty: Double? = nil, message: String? = nil) -> SubmitResult {
        return SubmitResult(
            accepted: false, 
            error: error, 
            jobId: jobId, 
            nonce: nonce,
            difficulty: difficulty,
            message: message
        )
    }
}
