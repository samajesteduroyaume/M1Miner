import Foundation
import M1MinerShared

/// Représente une requête Stratum
public struct StratumRequest: Codable {
    public let id: UInt64
    public let method: String
    public let params: [AnyDecodable]
    
    public init(id: UInt64, method: String, params: [AnyDecodable]) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Représente une réponse Stratum
public struct StratumResponse: Codable {
    // Implémentation manuelle de Encodable car AnyDecodable n'est pas Encodable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        // Ne pas encoder result car AnyDecodable n'est pas Encodable
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(method, forKey: .method)
        // Ne pas encoder params car [AnyDecodable] n'est pas Encodable
    }
    public let id: UInt64?
    public let result: AnyDecodable?
    public let error: StratumErrorResponse?
    public let method: String?
    public let params: [AnyDecodable]?
    
    public init(id: UInt64? = nil, 
                result: AnyDecodable? = nil, 
                error: StratumErrorResponse? = nil, 
                method: String? = nil, 
                params: [AnyDecodable]? = nil) {
        self.id = id
        self.result = result
        self.error = error
        self.method = method
        self.params = params
    }
}

/// Représente une erreur Stratum
public struct StratumErrorResponse: Codable, Error {
    public let code: Int
    public let message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
    
    /// Convertit l'erreur en dictionnaire
    public func toDictionary() -> [String: Any] {
        return [
            "code": code,
            "message": message
        ]
    }
}




// AnyDecodable est maintenant défini dans le fichier AnyDecodable.swift
