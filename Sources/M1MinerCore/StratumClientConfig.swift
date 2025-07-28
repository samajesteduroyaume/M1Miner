import Foundation
import NIO

/// Configuration pour le client Stratum
public struct StratumClientConfig {
    /// Hôte du pool de minage
    public let host: String
    
    /// Port du pool de minage
    public let port: Int
    
    /// Indique si la connexion doit utiliser TLS
    public let useTLS: Bool
    
    /// Adresse du portefeuille
    public let wallet: String
    
    /// Nom du worker
    public let worker: String
    
    /// Mot de passe du worker
    public let password: String
    
    /// Délai d'attente pour la connexion (en secondes)
    public let connectionTimeout: TimeInterval
    
    /// Délai d'attente pour la lecture (en secondes)
    public let readTimeout: TimeInterval
    
    /// Délai d'attente pour l'écriture (en secondes)
    public let writeTimeout: TimeInterval
    
    /// Initialise une nouvelle configuration pour le client Stratum
    /// - Parameters:
    ///   - host: Hôte du pool de minage
    ///   - port: Port du pool de minage
    ///   - useTLS: Indique si la connexion doit utiliser TLS (défaut: false)
    ///   - wallet: Adresse du portefeuille
    ///   - worker: Nom du worker (défaut: "worker1")
    ///   - password: Mot de passe du worker (défaut: "x")
    ///   - connectionTimeout: Délai d'attente pour la connexion (en secondes, défaut: 10)
    ///   - readTimeout: Délai d'attente pour la lecture (en secondes, défaut: 30)
    ///   - writeTimeout: Délai d'attente pour l'écriture (en secondes, défaut: 10)
    public init(
        host: String,
        port: Int,
        useTLS: Bool = false,
        wallet: String,
        worker: String = "worker1",
        password: String = "x",
        connectionTimeout: TimeInterval = 10,
        readTimeout: TimeInterval = 30,
        writeTimeout: TimeInterval = 10
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.wallet = wallet
        self.worker = worker
        self.password = password
        self.connectionTimeout = connectionTimeout
        self.readTimeout = readTimeout
        self.writeTimeout = writeTimeout
    }
}

// MARK: - Extensions utiles

extension StratumClientConfig: CustomStringConvertible {
    public var description: String {
        """
        StratumClientConfig:
          Host: \(host):\(port)\(useTLS ? " (TLS)" : "")
          Wallet: \(wallet)
          Worker: \(worker)
          Timeouts: connect=\(connectionTimeout)s, read=\(readTimeout)s, write=\(writeTimeout)s
        """
    }
}

extension StratumClientConfig: Equatable {
    public static func == (lhs: StratumClientConfig, rhs: StratumClientConfig) -> Bool {
        return lhs.host == rhs.host &&
               lhs.port == rhs.port &&
               lhs.useTLS == rhs.useTLS &&
               lhs.wallet == rhs.wallet &&
               lhs.worker == rhs.worker
    }
}
