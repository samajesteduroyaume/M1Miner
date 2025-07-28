import Foundation

/// Configuration du mineur
public struct MinerConfig: Codable, Sendable {
    // MARK: - Propriétés de configuration
    
    /// URL du pool de minage (format: stratum+tcp://adresse:port)
    public let poolUrl: String
    
    /// Adresse du portefeuille pour recevoir les récompenses
    public let walletAddress: String
    
    /// Nom du worker (optionnel)
    public let workerName: String
    
    /// Mot de passe du worker (généralement "x" ou vide)
    public let password: String
    
    /// Intensité du minage (1-30)
    public let intensity: Int
    
    /// Nombre de threads de minage
    public let threads: Int
    
    /// Algorithme de minage (ghostrider, kawpow, etc.)
    public let algorithm: String
    
    /// Pause en secondes avant de réessayer en cas d'erreur
    public let retryPause: Int
    
    /// Niveau de don (0-100)
    public let donateLevel: Int
    
    // MARK: - Propriétés calculées
    
    /// Liste des algorithmes supportés
    public static let supportedAlgorithms = ["ghostrider", "kawpow", "btg", "equihash"]
    
    /// Vérifie si la configuration est valide
    public var isValid: Bool {
        guard !poolUrl.isEmpty,
              !walletAddress.isEmpty,
              !workerName.isEmpty,
              intensity >= 1 && intensity <= 30,
              threads >= 1,
              !algorithm.isEmpty,
              MinerConfig.supportedAlgorithms.contains(algorithm.lowercased()) else {
            return false
        }
        return true
    }
    
    // MARK: - Initialisation

    
    public init(
        poolUrl: String,
        walletAddress: String,
        workerName: String = "m1miner",
        password: String = "x",
        intensity: Int = 20,
        threads: Int = 4,
        algorithm: String = "ghostrider",
        retryPause: Int = 5,
        donateLevel: Int = 1
    ) {
        self.poolUrl = poolUrl
        self.walletAddress = walletAddress
        self.workerName = workerName
        self.password = password
        self.intensity = max(1, min(30, intensity)) // Force entre 1 et 30
        self.threads = max(1, min(32, threads)) // Force entre 1 et 32 threads
        self.algorithm = algorithm
        self.retryPause = max(1, retryPause)
        self.donateLevel = max(0, min(100, donateLevel)) // Force entre 0 et 100
    }
    
    /// Charge la configuration depuis un fichier JSON
    public static func load(from path: String) -> MinerConfig? {
        let fileManager = FileManager.default
        
        // Vérifier si le fichier existe
        guard fileManager.fileExists(atPath: path) else {
            print("❌ Fichier de configuration non trouvé: \(path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            return try decoder.decode(MinerConfig.self, from: data)
        } catch {
            print("❌ Erreur lors du chargement de la configuration: \(error)")
            return nil
        }
    }
    
    /// Enregistre la configuration dans un fichier JSON
    public func save(to path: String) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            print("❌ Erreur lors de l'enregistrement de la configuration: \(error)")
            return false
        }
    }
}
