import Foundation
import NIO
import Foundation

// MARK: - Types partagés entre les modules

/// Représente un travail de minage reçu du serveur Stratum
public struct StratumJob: Codable, Sendable {
    // Constantes pour le calcul de la difficulté
    private enum Constants {
        static let maxTarget: Double = 0x00000000FFFF0000000000000000000000000000000000000000000000000000
    }
    
    /// Retourne la difficulté calculée à partir de nBits
    public var difficulty: Double {
        // Convertir nBits de hexadécimal à un entier
        guard let nBitsValue = UInt32(nBits, radix: 16) else { return 0 }
        
        // Extraire l'exposant et le coefficient (format compact de Bitcoin)
        let exponent = nBitsValue >> 24
        let coefficient = nBitsValue & 0x007fffff
        
        // Calculer la cible
        let target: Double
        if exponent <= 3 {
            target = Double(coefficient) / Double(256.0 * Double(3 - exponent))
        } else {
            target = Double(coefficient) * Double(pow(256.0, Double(exponent - 3)))
        }
        
        // Éviter la division par zéro
        guard target > 0 else { return 0 }
        
        // Calculer la difficulté (difficulté maximale / cible)
        return Constants.maxTarget / target
    }
    /// Identifiant unique du travail
    public let jobId: String
    
    /// Hash du bloc précédent (little-endian)
    public let prevHash: String
    
    /// Première partie de la coinbase (en-tête de transaction)
    public let coinbase1: String
    
    /// Seconde partie de la coinbase (sortie de transaction)
    public let coinbase2: String
    
    /// Branches Merkle pour la construction de l'arbre Merkle
    public let merkleBranches: [String]
    
    /// Version du bloc (little-endian)
    public let version: String
    
    /// Cible de difficulté (nBits au format compact)
    public let nBits: String
    
    /// Horodatage du bloc (little-endian)
    public let nTime: String
    
    /// Indique si les travaux précédents doivent être abandonnés
    public let cleanJobs: Bool
    
    /// Données supplémentaires pour l'algorithme GhostRider (optionnel)
    public struct GhostRiderData: Codable, Sendable {
        /// Données d'entrée pour l'algorithme GhostRider
        public let input: [UInt8]
        /// Target pour l'algorithme GhostRider
        public let target: [UInt8]
        
        public init(input: [UInt8], target: [UInt8]) {
            self.input = input
            self.target = target
        }
    }
    
    /// Données spécifiques à l'algorithme GhostRider (optionnel)
    public let ghostRiderData: GhostRiderData?
    
    /// Target pour la soumission des shares (optionnel, spécifique à certains pools)
    public let target: String?
    
    /// Données d'extranonce
    public let extranonce1: String
    public let extranonce2Size: Int
    
    public init(
        jobId: String,
        prevHash: String,
        coinbase1: String,
        coinbase2: String,
        merkleBranches: [String],
        version: String,
        nBits: String,
        nTime: String,
        cleanJobs: Bool,
        extranonce1: String = "",
        extranonce2Size: Int = 4,
        target: String? = nil,
        ghostRiderData: GhostRiderData? = nil
    ) {
        self.jobId = jobId
        self.prevHash = prevHash
        self.coinbase1 = coinbase1
        self.coinbase2 = coinbase2
        self.merkleBranches = merkleBranches
        self.version = version
        self.nBits = nBits
        self.nTime = nTime
        self.cleanJobs = cleanJobs
        self.extranonce1 = extranonce1
        self.extranonce2Size = extranonce2Size
        self.target = target
        self.ghostRiderData = ghostRiderData
    }
    
    /// Génère les données d'en-tête pour le hachage
    public func headerData() -> Data? {
        var data = Data()
        
        // Convertir la version en little-endian
        guard let versionData = self.version.hexData?.reversed() else { return nil }
        data.append(contentsOf: versionData)
        
        // Convertir le hash du bloc précédent en little-endian
        guard let prevHashData = self.prevHash.hexData?.reversed() else { return nil }
        data.append(contentsOf: prevHashData)
        
        // Ajouter la racine Merkle (pour l'instant vide, sera calculée plus tard)
        let merkleRootPlaceholder = Data(repeating: 0, count: 32)
        data.append(merkleRootPlaceholder)
        
        // Convertir l'horodatage en little-endian
        guard let timeData = self.nTime.hexData?.reversed() else { return nil }
        data.append(contentsOf: timeData)
        
        // Convertir la difficulté en little-endian
        guard let bitsData = self.nBits.hexData?.reversed() else { return nil }
        data.append(contentsOf: bitsData)
        
        return data
    }
}

// Extension pour CharacterSet avec les caractères hexadécimaux
extension CharacterSet {
    /// Caractères hexadécimaux valides (0-9, a-f, A-F)
    public static var hexadecimal: CharacterSet {
        return CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    }
}

// Extension pour convertir une chaîne hexadécimale en Data
public extension String {
    var hexData: Data? {
        var data = Data()
        var hexString = self
        
        // Supprimer le préfixe 0x si présent
        if hexString.hasPrefix("0x") {
            hexString = String(hexString.dropFirst(2))
        }
        
        // Vérifier que la longueur est paire
        guard hexString.count % 2 == 0 else { return nil }
        
        // Convertir chaque paire de caractères en octet
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]
            
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            
            index = nextIndex
        }
        
        return data
    }
}

/// Réponse du serveur Stratum
public struct StratumResponse: Codable {
    /// Identifiant de la requête
    public let id: Int
    
    /// Résultat de la requête (peut être de différents types)
    public let result: JSONValue?
    
    /// Erreur éventuelle
    public let error: [String: JSONValue]?
    
    /// Indique si la réponse est un succès
    public var isSuccess: Bool {
        return error == nil
    }
    
    // Implémentation manuelle de Codable pour gérer le type Any
    private enum CodingKeys: String, CodingKey {
        case id, result, error
    }
    
    public init(id: Int, result: Any? = nil, error: [String: Any]? = nil) {
        self.id = id
        self.result = JSONValue(any: result)
        self.error = error?.mapValues { JSONValue(any: $0) }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        error = try container.decodeIfPresent([String: JSONValue].self, forKey: .error)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }
    
    // Helper pour accéder au résultat avec le type attendu
    public func resultValue<T>() -> T? {
        return result?.anyValue as? T
    }
    
    // Helper pour accéder à une valeur d'erreur avec le type attendu
    public func errorValue<T>(forKey key: String) -> T? {
        return error?[key]?.anyValue as? T
    }
}

// Type pour gérer les valeurs JSON de manière type-safe
public enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    public init(any: Any?) {
        switch any {
        case let value as String: self = .string(value)
        case let value as Int: self = .int(value)
        case let value as Double: self = .double(value)
        case let value as Bool: self = .bool(value)
        case let value as [String: Any]:
            self = .object(value.mapValues { JSONValue(any: $0) })
        case let value as [Any]:
            self = .array(value.map { JSONValue(any: $0) })
        case nil, is NSNull: self = .null
        default:
            // Tenter de convertir en String comme dernier recours
            self = .string(String(describing: any))
        }
    }
    
    public var anyValue: Any? {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues { $0.anyValue }
        case .array(let value): return value.map { $0.anyValue }
        case .null: return nil
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// StratumError a été déplacé vers M1MinerCore/Stratum/StratumModels.swift
// Utilisez `import M1MinerCore` pour y accéder

/// Erreurs réseau communes
public enum NetworkError: Error, Equatable {
    case alreadyConnected
    case notConnected
    case connectionFailed(Error)
    case connectionClosed
    case timeout
    case invalidState
    case invalidResponse
    case requestCancelled
    case shuttingDown
    case deallocated
    case sslError(Error)
    case invalidURL
    
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.alreadyConnected, .alreadyConnected):
            return true
        case (.notConnected, .notConnected):
            return true
        case (.connectionClosed, .connectionClosed):
            return true
        case (.timeout, .timeout):
            return true
        case (.invalidState, .invalidState):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.requestCancelled, .requestCancelled):
            return true
        case (.shuttingDown, .shuttingDown):
            return true
        case (.deallocated, .deallocated):
            return true
        case (.invalidURL, .invalidURL):
            return true
        case (.connectionFailed(let lhsError), .connectionFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.sslError(let lhsError), .sslError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Protocoles partagés

// Le protocole StratumClientProtocol est maintenant défini dans StratumClientProtocols.swift
// Utilisez `import StratumClientProtocols` pour y accéder

/// Protocole pour la stratégie de minage
public protocol MiningStrategy: AnyObject {
    /// Démarre la stratégie de minage
    func start() async throws
    
    /// Arrête la stratégie de minage
    func stop()
    
    /// Traite un nouveau travail de minage
    /// - Parameter job: Le nouveau travail à traiter
    func handleNewJob(_ job: StratumJob) async
    
    /// Délégué pour les événements de la stratégie
    var delegate: MiningStrategyDelegate? { get set }
}

/// Délégué pour la stratégie de minage
public protocol MiningStrategyDelegate: AnyObject {
    /// Appelé lorsqu'une part valide est trouvée
    /// - Parameter share: La part trouvée
    func didFindShare(_ share: Share)
    
    /// Appelé lorsqu'une erreur survient
    /// - Parameter error: L'erreur rencontrée
    func didEncounterError(_ error: Error)
    
    /// Appelé lorsque les statistiques sont mises à jour
    /// - Parameter stats: Les nouvelles statistiques
    func didUpdateStats(_ stats: MiningStats)
}

/// Représente une part soumise au pool
public struct Share: Codable {
    /// Identifiant du travail
    public let jobId: String
    
    /// Deuxième partie de l'extranonce
    public let extranonce2: String
    
    /// Horodatage du bloc (format hexadécimal)
    public let ntime: String
    
    /// Nonce trouvé
    public let nonce: String
    
    /// Difficulté du travail
    public let difficulty: Double
    
    /// Horodatage de la soumission
    public let timestamp: Date
    
    /// Initialise une nouvelle part
    /// - Parameters:
    ///   - jobId: Identifiant du travail
    ///   - extranonce2: Deuxième partie de l'extranonce
    ///   - ntime: Horodatage du bloc (format hexadécimal)
    ///   - nonce: Nonce trouvé
    ///   - difficulty: Difficulté du travail
    public init(jobId: String, extranonce2: String, ntime: String, nonce: String, difficulty: Double) {
        self.jobId = jobId
        self.extranonce2 = extranonce2
        self.ntime = ntime
        self.nonce = nonce
        self.difficulty = difficulty
        self.timestamp = Date()
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case jobId, extranonce2, ntime, nonce, difficulty, timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(String.self, forKey: .jobId)
        extranonce2 = try container.decode(String.self, forKey: .extranonce2)
        ntime = try container.decode(String.self, forKey: .ntime)
        nonce = try container.decode(String.self, forKey: .nonce)
        difficulty = try container.decode(Double.self, forKey: .difficulty)
        timestamp = (try? container.decodeIfPresent(Date.self, forKey: .timestamp)) ?? Date()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(extranonce2, forKey: .extranonce2)
        try container.encode(ntime, forKey: .ntime)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

/// Statistiques de minage
public struct MiningStats: Codable {
    /// Taux de hachage en H/s
    public let hashrate: Double
    
    /// Nombre de parts acceptées
    public let sharesAccepted: Int
    
    /// Nombre de parts rejetées
    public let sharesRejected: Int
    
    /// Dernière part soumise
    public let lastShareTime: Date?
    
    /// Initialise de nouvelles statistiques
    /// - Parameters:
    ///   - hashrate: Taux de hachage en H/s
    ///   - sharesAccepted: Nombre de parts acceptées
    ///   - sharesRejected: Nombre de parts rejetées
    ///   - lastShareTime: Dernière part soumise
    public init(hashrate: Double, sharesAccepted: Int, sharesRejected: Int, lastShareTime: Date? = nil) {
        self.hashrate = hashrate
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.lastShareTime = lastShareTime
    }
}

// MARK: - Types pour le client Stratum

/// Statistiques de connexion du client Stratum
public struct ConnectionStats: Codable, Sendable {
    // Propriétés de connexion
    public var totalConnections: Int = 0
    public var disconnectionCount: Int = 0
    public var lastConnectionTime: Date?
    public var lastDisconnectTime: Date?
    public var lastConnectTime: Date?
    public var connectionStartTime: Date?
    public var isConnected: Bool = false
    
    // Propriétés de trafic réseau
    public var totalBytesSent: Int = 0
    public var totalBytesReceived: Int = 0
    public var totalRequestsSent: Int = 0
    public var totalResponsesReceived: Int = 0
    
    // Propriétés d'erreur
    public var totalErrors: Int = 0
    public var lastErrorDescription: String?
    
    // Propriétés temporelles
    public var lastActivityTime: Date?
    public var lastSessionDuration: TimeInterval = 0
    
    // Propriétés de travail
    public var jobsReceived: Int = 0
    public var acceptedShares: Int = 0
    public var rejectedShares: Int = 0
    public var lastShareTime: Date?
    public var hashrate: Double = 0.0
    public var difficulty: Double = 0.0
    
    // Propriétés calculées
    public var connectionDuration: TimeInterval {
        guard let start = connectionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    public init() {}
}

/// Statistiques du client Stratum
public struct StratumClientStats: Codable, Sendable {
    /// Nombre de requêtes en attente
    public var pendingRequests: Int
    
    /// Nombre de requêtes envoyées
    public var requestsSent: Int
    
    /// Nombre de réponses reçues
    public var responsesReceived: Int
    
    /// Nombre de notifications reçues
    public var notificationsReceived: Int
    
    /// Dernière erreur rencontrée
    public var lastError: String?
    
    /// Date de début de la connexion
    public var connectionStartTime: Date
    
    /// Temps de connexion en secondes
    public var uptime: TimeInterval {
        return Date().timeIntervalSince(connectionStartTime)
    }
    
    /// Latence moyenne du réseau en millisecondes
    public var networkLatency: Double
    
    /// Nombre de parts acceptées
    public var sharesAccepted: Int
    
    /// Nombre de parts rejetées
    public var sharesRejected: Int
    
    // Propriétés supplémentaires pour la gestion des statistiques réseau
    /// Nombre total d'octets reçus
    public var totalBytesReceived: UInt64
    
    /// Nombre total d'erreurs
    public var totalErrors: UInt64
    
    /// Nombre total de requêtes envoyées
    public var totalRequestsSent: UInt64
    
    /// Nombre de parts acceptées (alias pour compatibilité)
    public var acceptedShares: Int {
        get { return sharesAccepted }
        set { sharesAccepted = newValue }
    }
    
    /// Nombre de travaux reçus
    public var jobsReceived: Int
    
    /// Date de la dernière déconnexion
    public var lastDisconnectTime: Date?
    
    /// Nombre total de déconnexions
    public var totalDisconnects: UInt64 = 0
    
    /// Initialise de nouvelles statistiques
    public init(pendingRequests: Int = 0, 
                requestsSent: Int = 0, 
                responsesReceived: Int = 0, 
                notificationsReceived: Int = 0, 
                lastError: String? = nil,
                connectionStartTime: Date = Date(),
                networkLatency: Double = 0,
                sharesAccepted: Int = 0,
                sharesRejected: Int = 0,
                jobsReceived: Int = 0,
                totalBytesReceived: UInt64 = 0,
                totalErrors: UInt64 = 0,
                totalRequestsSent: UInt64 = 0) {
        self.connectionStartTime = connectionStartTime
        self.pendingRequests = pendingRequests
        self.requestsSent = requestsSent
        self.responsesReceived = responsesReceived
        self.notificationsReceived = notificationsReceived
        self.lastError = lastError
        self.networkLatency = networkLatency
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.jobsReceived = jobsReceived
        self.totalBytesReceived = totalBytesReceived
        self.totalErrors = totalErrors
        self.totalRequestsSent = totalRequestsSent
    }
}

/// Erreurs spécifiques au client Stratum
public enum StratumClientError: Error, Equatable {
    /// Échec de la connexion au serveur
    case connectionFailed(String)
    
    /// Déconnexion inattendue
    case disconnected
    
    /// Échec de l'authentification
    case authenticationFailed(String)
    
    /// Échec de la soumission d'une part
    case submitFailed(String)
    
    /// Réponse invalide du serveur
    case invalidResponse(String)
    
    /// État interne invalide
    case invalidState(String)
    
    /// Requête expirée
    case requestTimeout
    
    /// Erreur inconnue
    case unknown(String)
    
    // Implémentation de Equatable
    public static func == (lhs: StratumClientError, rhs: StratumClientError) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.requestTimeout, .requestTimeout):
            return true
            
        case (.connectionFailed(let lhsMsg), .connectionFailed(let rhsMsg)),
             (.authenticationFailed(let lhsMsg), .authenticationFailed(let rhsMsg)),
             (.submitFailed(let lhsMsg), .submitFailed(let rhsMsg)),
             (.invalidResponse(let lhsMsg), .invalidResponse(let rhsMsg)),
             (.unknown(let lhsMsg), .unknown(let rhsMsg)):
            return lhsMsg == rhsMsg
            
        default:
            return false
        }
    }
    
    /// Description de l'erreur
    public var description: String {
        switch self {
        case .connectionFailed(let message):
            return "Échec de la connexion: \(message)"
        case .disconnected:
            return "Déconnecté du serveur"
        case .authenticationFailed(let reason):
            return "Échec de l'authentification: \(reason)"
        case .submitFailed(let reason):
            return "Échec de la soumission: \(reason)"
        case .invalidResponse(let details):
            return "Réponse invalide du serveur: \(details)"
        case .invalidState(let details):
            return "État interne invalide: \(details)"
        case .requestTimeout:
            return "Délai d'attente dépassé"
        case .unknown(let details):
            return "Erreur inconnue: \(details)"
        }
    }
}
