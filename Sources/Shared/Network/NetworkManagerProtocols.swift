import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOSSL
import Logging

/// État de la connexion réseau
public enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// Protocole pour gérer les événements réseau
public protocol NetworkManagerDelegate: AnyObject, Sendable {
    /// Appelé lorsque la connexion est établie avec succès
    /// - Parameters:
    ///   - manager: Le NetworkManager qui a établi la connexion
    ///   - host: L'hôte auquel on est connecté
    ///   - port: Le port utilisé pour la connexion
    func networkManager(_ manager: any NetworkManager, didConnectToHost host: String, port: Int)
    
    /// Appelé lorsque la connexion est perdue
    /// - Parameters:
    ///   - manager: Le NetworkManager qui a perdu la connexion
    ///   - error: L'erreur éventuelle qui a causé la déconnexion
    func networkManager(_ manager: any NetworkManager, didDisconnectWithError error: Error?)
    
    /// Appelé lorsque des données sont reçues du serveur
    /// - Parameters:
    ///   - manager: Le NetworkManager qui a reçu les données
    ///   - data: Les données reçues
    func networkManager(_ manager: any NetworkManager, didReceiveData data: Data)
    
    /// Appelé lorsqu'une erreur se produit dans le NetworkManager
    /// - Parameters:
    ///   - manager: Le NetworkManager qui a rencontré l'erreur
    ///   - error: L'erreur survenue
    func networkManager(_ manager: any NetworkManager, didEncounterError error: Error)
}

// Implémentations par défaut optionnelles
public extension NetworkManagerDelegate {
    func networkManager(_ manager: any NetworkManager, didConnectToHost host: String, port: Int) {}
    func networkManager(_ manager: any NetworkManager, didDisconnectWithError error: Error?) {}
    func networkManager(_ manager: any NetworkManager, didReceiveData data: Data) {}
    func networkManager(_ manager: any NetworkManager, didEncounterError error: Error) {}
}

/// Protocole définissant les fonctionnalités d'un gestionnaire de réseau
public protocol NetworkManager: AnyObject, Sendable {
    /// Délégé pour les événements réseau
    var delegate: (any NetworkManagerDelegate)? { get set }
    
    /// État actuel de la connexion
    var connectionState: ConnectionState { get }
    
    /// Se connecte à l'hôte et au port spécifiés
    /// - Parameters:
    ///   - host: L'hôte auquel se connecter
    ///   - port: Le port à utiliser
    ///   - completion: Callback appelé lorsque la tentative de connexion est terminée
    func connect(host: String, port: Int, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Déconnecte le gestionnaire réseau
    func disconnect()
    
    /// Envoie des données via la connexion réseau
    /// - Parameters:
    ///   - data: Les données à envoyer
    ///   - completion: Callback appelé lorsque l'envoi est terminé
    func send(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void)
}

// Extension pour la compatibilité avec Sendable
#if compiler(>=5.5) && canImport(_Concurrency)
extension NetworkManager {
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    public func connect(host: String, port: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connect(host: host, port: port) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            send(data) { result in
                continuation.resume(with: result)
            }
        }
    }
}
#endif
