import Foundation
import NIO
import NIOConcurrencyHelpers
import Logging

// MARK: - Protocoles Stratum consolidés

/// Protocole pour les clients Stratum (version consolidée)
public protocol StratumClientInterface: AnyObject, Sendable {
    // MARK: - Propriétés de base
    
    /// État de connexion actuel du client
    var isConnected: Bool { get }
    
    /// Travail de minage actuel
    var currentJob: StratumJob? { get }
    
    /// Difficulté actuelle du travail
    var currentDifficulty: Double { get }
    
    /// Statistiques du client
    var stats: ConnectionStats { get }
    
    /// Délégué pour recevoir les événements du client
    var delegate: StratumClientDelegate? { get set }
    
    // MARK: - Méthodes de connexion
    
    /// Établit une connexion avec le serveur
    /// - Parameters:
    ///   - host: L'hôte du serveur
    ///   - port: Le port du serveur
    ///   - useTLS: Indique si la connexion doit utiliser TLS
    ///   - workerName: Le nom du worker pour l'authentification
    ///   - password: Le mot de passe pour l'authentification
    ///   - completion: Callback appelé lorsque la connexion est établie ou a échoué
    func connect(host: String, port: Int, useTLS: Bool, workerName: String, password: String, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Ferme la connexion avec le serveur
    func disconnect()
    
    // MARK: - Méthodes de minage
    
    /// Soumet une solution de minage au serveur
    /// - Parameters:
    ///   - worker: Nom du worker
    ///   - jobId: Identifiant du travail
    ///   - nonce: Nonce de la solution
    ///   - result: Résultat du hachage
    ///   - completion: Callback appelé avec le résultat de la soumission
    func submit(worker: String, jobId: String, nonce: String, result: String, completion: @escaping (Result<Bool, Error>) -> Void)
}

/// Protocole pour les délégués du client Stratum (version consolidée)
public protocol StratumClientDelegate: AnyObject, Sendable {
    // MARK: - Événements de connexion
    
    /// Appelé lorsque l'état de la connexion change
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - isConnected: Nouvel état de la connexion
    func stratumClient(_ client: StratumClientInterface, didChangeConnectionState isConnected: Bool)
    
    /// Appelé lorsque le client se connecte avec succès au serveur
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - host: L'hôte auquel le client est connecté
    ///   - port: Le port de connexion
    func stratumClient(_ client: StratumClientInterface, didConnectToHost host: String, port: Int)
    
    /// Appelé lorsque le client se déconnecte du serveur
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - error: L'erreur qui a causé la déconnexion, si applicable
    func stratumClientDidDisconnect(_ client: StratumClientInterface, error: Error?)
    
    // MARK: - Événements de minage
    
    /// Appelé lorsque le client reçoit un nouveau travail de minage
    /// - Parameters:
    ///   - client: Le client Stratum qui a reçu le travail
    ///   - job: Le travail de minage reçu
    func stratumClient(_ client: StratumClientInterface, didReceiveJob job: StratumJob)
    
    /// Appelé lorsque la difficulté du pool est mise à jour
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - difficulty: La nouvelle difficulté
    func stratumClient(_ client: StratumClientInterface, didUpdateDifficulty difficulty: Double)
    
    /// Appelé lorsque les statistiques du client sont mises à jour
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - stats: Nouvelles statistiques
    func stratumClient(_ client: StratumClientInterface, didUpdateStats stats: ConnectionStats)
    
    // MARK: - Gestion des erreurs
    
    /// Appelé lorsqu'une erreur se produit
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - error: L'erreur qui s'est produite
    func stratumClient(_ client: StratumClientInterface, didReceiveError error: Error)
    
    /// Appelé lorsqu'une notification est reçue du serveur
    /// - Parameters:
    ///   - client: Le client Stratum
    ///   - notification: Le nom de la notification
    ///   - params: Les paramètres de la notification
    func stratumClient(_ client: StratumClientInterface, didReceiveNotification notification: String, params: [Any])
}

// MARK: - Types associés

// Les protocoles ci-dessus utilisent désormais les types SubmitResult (struct) et StratumClientError (enum) définis dans leurs fichiers respectifs.
// Veillez à référencer ces types dans les signatures de méthode si besoin.

// MARK: - Extensions utiles

extension StratumClientInterface {
    /// Version simplifiée de la méthode de connexion
    public func connect(to url: URL, worker: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let host = url.host, let port = url.port else {
            completion(.failure(StratumClientError.invalidState("URL invalide")))
            return
        }
        
        let useTLS = url.scheme?.lowercased() == "stratum+ssl" || url.scheme?.lowercased() == "stratum+tls"
        connect(host: host, port: port, useTLS: useTLS, workerName: worker, password: password, completion: completion)
    }
}
