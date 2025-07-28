import Foundation
import NIO

/// Protocole pour recevoir les événements du NetworkManager
public protocol NetworkManagerDelegate: AnyObject {
    /// Appelé lorsque des données sont reçues du serveur
    /// - Parameters:
    ///   - manager: Le NetworkManager qui a reçu les données
    ///   - data: Les données reçues
    func networkManager(_ manager: NetworkManager, didReceiveData data: Data)
    
    /// Appelé lorsque la connexion est établie avec succès
    /// - Parameter manager: Le NetworkManager dont la connexion est établie
    func networkManagerDidConnect(_ manager: NetworkManager)
    
    /// Appelé lorsque la connexion est perdue ou fermée
    /// - Parameters:
    ///   - manager: Le NetworkManager dont la connexion est perdue
    ///   - error: L'erreur éventuelle qui a causé la déconnexion
    func networkManager(_ manager: NetworkManager, didDisconnectWithError error: Error?)
    
    /// Appelé lorsqu'une erreur se produit dans le NetworkManager
    /// - Parameters:
    ///   - manager: Le NetworkManager qui a rencontré l'erreur
    ///   - error: L'erreur survenue
    func networkManager(_ manager: NetworkManager, didEncounterError error: Error)
}
