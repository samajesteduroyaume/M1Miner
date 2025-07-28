import Foundation
import NIO
import M1MinerShared

/// Adaptateur qui fait le pont entre les deux versions du protocole NetworkManagerDelegate
final class NetworkManagerAdapter: @unchecked Sendable {
    private let delegate: NetworkManagerDelegate
    private let logger: Logger
    
    init(delegate: NetworkManagerDelegate, logger: Logger) {
        self.delegate = delegate
        self.logger = logger
    }
    
    // MARK: - Méthodes de conformité avec M1MinerShared.NetworkManagerDelegate
    
    func networkManager(_ manager: M1MinerShared.NetworkManager, didConnectToHost host: String, port: Int) {
        logger.debug("🔌 Adaptateur: Connexion établie avec succès à \(host):\(port)")
        delegate.networkManager(manager, didConnectToHost: host, port: port)
    }
    
    func networkManager(_ manager: M1MinerShared.NetworkManager, didDisconnectWithError error: Error?) {
        logger.debug("🔌 Adaptateur: Déconnexion du serveur")
        delegate.networkManager(manager, didDisconnectWithError: error)
    }
    
    func networkManager(_ manager: M1MinerShared.NetworkManager, didReceiveData data: Data) {
        logger.debug("🔌 Adaptateur: Données reçues (\(data.count) octets)")
        delegate.networkManager(manager, didReceiveData: data)
    }
    
    func networkManager(_ manager: M1MinerShared.NetworkManager, didEncounterError error: Error) {
        logger.error("🔌 Adaptateur: Erreur réseau - \(error.localizedDescription)")
        delegate.networkManager(manager, didEncounterError: error)
    }
}
