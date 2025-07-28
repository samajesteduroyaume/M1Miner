import Foundation

/// Représente une notification du serveur Stratum
public struct StratumNotification: Codable {
    /// Méthode de la notification (ex: "mining.notify", "mining.set_difficulty")
    public let method: String
    
    /// Paramètres de la notification
    public let params: JSONValue
    
    /// ID de la notification (peut être nul pour certaines notifications)
    public let id: Int?
    
    /// Initialise une nouvelle notification
    public init(method: String, params: JSONValue, id: Int? = nil) {
        self.method = method
        self.params = params
        self.id = id
    }
    
    // Implémentation manuelle de Codable pour gérer le type Any
    private enum CodingKeys: String, CodingKey {
        case method, params, id
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decode(JSONValue.self, forKey: .params)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
        try container.encodeIfPresent(id, forKey: .id)
    }
}

// Extension pour faciliter la conversion depuis les données brutes
extension StratumNotification {
    /// Tente de créer une StratumNotification à partir de données JSON brutes
    public static func from(data: Data) throws -> StratumNotification? {
        // Vérifier si c'est un objet JSON valide
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Vérifier si c'est une notification (doit avoir une méthode)
        guard let method = json["method"] as? String else {
            return nil
        }
        
        // Extraire les paramètres
        let params = json["params"] ?? []
        let id = json["id"] as? Int
        
        return StratumNotification(
            method: method,
            params: JSONValue(any: params),
            id: id
        )
    }
}
