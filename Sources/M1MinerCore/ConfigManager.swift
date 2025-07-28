import Foundation

/// Gère le chargement et la validation de la configuration du mineur
public class ConfigManager {
    
    // MARK: - Types
    
    /// Structure représentant la configuration du mineur
    public struct Configuration: Codable {
        /// URL du pool de minage (ex: "stratum+ssl://rvn.2miners.com:6060")
        public let poolUrl: String
        
        /// Adresse du portefeuille pour recevoir les récompenses
        public let walletAddress: String
        
        /// Nom du worker (optionnel)
        public let workerName: String
        
        /// Intensité du minage (1-10)
        public let intensity: Int
        
        /// Démarrer automatiquement le minage au lancement
        public let autoStart: Bool
        
        /// Niveau de journalisation (debug, info, warning, error)
        public let logLevel: String
        
        /// Configuration de l'API
        public let api: APIConfig?
        
        /// Options avancées
        public let advanced: AdvancedConfig?
        
        public init(poolUrl: String, 
                   walletAddress: String, 
                   workerName: String = "m1miner", 
                   intensity: Int = 8, 
                   autoStart: Bool = true, 
                   logLevel: String = "info",
                   api: APIConfig? = nil,
                   advanced: AdvancedConfig? = nil) {
            self.poolUrl = poolUrl
            self.walletAddress = walletAddress
            self.workerName = workerName
            self.intensity = max(1, min(10, intensity))
            self.autoStart = autoStart
            self.logLevel = logLevel
            self.api = api
            self.advanced = advanced
        }
    }
    
    /// Configuration de l'API
    public struct APIConfig: Codable {
        /// Activer/désactiver l'API
        public let enabled: Bool
        
        /// Port d'écoute de l'API
        public let port: Int
        
        /// Clé d'API pour l'authentification
        public let apiKey: String
        
        public init(enabled: Bool = false, port: Int = 8080, apiKey: String = "") {
            self.enabled = enabled
            self.port = port
            self.apiKey = apiKey.isEmpty ? UUID().uuidString : apiKey
        }
    }
    
    /// Configuration avancée
    public struct AdvancedConfig: Codable {
        /// Température maximale avant réduction de la puissance
        public let maxTemp: Int
        
        /// Vitesse du ventilateur ("auto" ou pourcentage 0-100)
        public let fanSpeed: String
        
        /// Limite de puissance (0-100%)
        public let powerLimit: Int
        
        /// Nombre de threads à utiliser (0 = auto)
        public let threads: Int
        
        /// Taille des groupes de travail
        public let worksize: Int
        
        /// Affinité des processeurs
        public let affinity: Int
        
        /// Désactiver la vérification SSL (déconseillé)
        public let noStrictSSL: Bool
        
        /// Pause en secondes entre les tentatives de reconnexion
        public let retryPause: Int
        
        /// Niveau de don (0-100%)
        public let donateLevel: Int
        
        public init(maxTemp: Int = 85,
                  fanSpeed: String = "auto",
                  powerLimit: Int = 80,
                  threads: Int = 0,
                  worksize: Int = 8,
                  affinity: Int = 0,
                  noStrictSSL: Bool = false,
                  retryPause: Int = 5,
                  donateLevel: Int = 1) {
            self.maxTemp = maxTemp
            self.fanSpeed = fanSpeed
            self.powerLimit = max(0, min(100, powerLimit))
            self.threads = max(0, threads)
            self.worksize = max(1, worksize)
            self.affinity = max(0, affinity)
            self.noStrictSSL = noStrictSSL
            self.retryPause = max(1, retryPause)
            self.donateLevel = max(0, min(100, donateLevel))
        }
    }
    
    // MARK: - Propriétés
    
    /// Configuration par défaut
    public static let `default` = Configuration(
        poolUrl: "stratum+ssl://rvn.2miners.com:6060",
        walletAddress: "VOTRE_ADRESSE_DE_PORTEFEUILLE",
        workerName: "m1miner",
        intensity: 8,
        autoStart: true,
        logLevel: "info",
        api: APIConfig(),
        advanced: AdvancedConfig()
    )
    
    // MARK: - Méthodes publiques
    
    /// Charge la configuration à partir d'un fichier
    /// - Parameter path: Chemin vers le fichier de configuration
    /// - Returns: Configuration chargée ou configuration par défaut en cas d'erreur
    public static func load(from path: String) -> Configuration {
        let fileManager = FileManager.default
        
        // Vérifier si le fichier existe
        guard fileManager.fileExists(atPath: path) else {
            print("⚠️ Fichier de configuration non trouvé à \(path). Utilisation de la configuration par défaut.")
            return `default`
        }
        
        do {
            // Lire le contenu du fichier
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            
            // Décoder la configuration
            let decoder = JSONDecoder()
            let config = try decoder.decode(Configuration.self, from: data)
            
            // Valider la configuration
            try validate(config)
            
            print("✅ Configuration chargée depuis \(path)")
            return config
            
        } catch {
            print("⚠️ Erreur lors du chargement de la configuration: \(error.localizedDescription)")
            print("ℹ️ Utilisation de la configuration par défaut.")
            return `default`
        }
    }
    
    /// Enregistre la configuration dans un fichier
    /// - Parameters:
    ///   - config: Configuration à enregistrer
    ///   - path: Chemin où enregistrer le fichier
    public static func save(_ config: Configuration, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    
    /// Valide une configuration
    /// - Parameter config: Configuration à valider
    public static func validate(_ config: Configuration) throws {
        // Vérifier l'URL du pool
        guard let url = URL(string: config.poolUrl),
              let scheme = url.scheme?.lowercased(),
              (scheme == "stratum+tcp" || scheme == "stratum+ssl" || 
               scheme == "http" || scheme == "https") else {
            throw ConfigError.invalidPoolURL
        }
        
        // Vérifier l'adresse du portefeuille
        guard !config.walletAddress.isEmpty,
              config.walletAddress.count >= 26, // Longueur minimale d'une adresse RVN
              config.walletAddress.count <= 35 else { // Longueur maximale d'une adresse RVN
            throw ConfigError.invalidWalletAddress
        }
        
        // Vérifier le niveau d'intensité
        guard (1...10).contains(config.intensity) else {
            throw ConfigError.invalidIntensity
        }
        
        // Valider la configuration avancée si elle existe
        if let advanced = config.advanced {
            guard (0...100).contains(advanced.powerLimit) else {
                throw ConfigError.invalidPowerLimit
            }
            
            guard (0...100).contains(advanced.donateLevel) else {
                throw ConfigError.invalidDonateLevel
            }
            
            if advanced.fanSpeed != "auto" {
                guard let fanSpeed = Int(advanced.fanSpeed),
                      (0...100).contains(fanSpeed) else {
                    throw ConfigError.invalidFanSpeed
                }
            }
        }
    }
    
    // MARK: - Types d'erreur
    
    public enum ConfigError: LocalizedError {
        case fileNotFound
        case invalidPoolURL
        case invalidWalletAddress
        case invalidIntensity
        case invalidPowerLimit
        case invalidDonateLevel
        case invalidFanSpeed
        case decodingError(Error)
        case encodingError(Error)
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Fichier de configuration introuvable"
            case .invalidPoolURL:
                return "URL du pool invalide. Doit commencer par 'stratum+tcp://', 'stratum+ssl://', 'http://' ou 'https://'"
            case .invalidWalletAddress:
                return "Adresse de portefeuille invalide"
            case .invalidIntensity:
                return "L'intensité doit être comprise entre 1 et 10"
            case .invalidPowerLimit:
                return "La limite de puissance doit être comprise entre 0 et 100%"
            case .invalidDonateLevel:
                return "Le niveau de don doit être compris entre 0 et 100%"
            case .invalidFanSpeed:
                return "La vitesse du ventilateur doit être 'auto' ou un pourcentage entre 0 et 100"
            case .decodingError(let error):
                return "Erreur de décodage de la configuration: \(error.localizedDescription)"
            case .encodingError(let error):
                return "Erreur d'encodage de la configuration: \(error.localizedDescription)"
            }
        }
    }
}
