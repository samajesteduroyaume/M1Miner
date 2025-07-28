import Foundation
import StratumClientNIO
import Logging
import M1MinerShared

/// Gère les opérations de minage en utilisant StratumClientNIO
public final class MiningManager {
    // MARK: - Types
    
    /// État du gestionnaire de minage
    public enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(Error)
        
        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (State.stopped, State.stopped), (.starting, .starting), (State.running, State.running), (.stopping, .stopping):
                return true
            case (.error(let lhsError), .error(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }
    
    /// Configuration du gestionnaire de minage
    public struct Configuration {
        public let poolHost: String
        public let poolPort: Int
        public let useTLS: Bool
        public let workerName: String
        public let password: String
        public let maxHashrate: Double // en H/s
        public let autoReconnect: Bool
        public let maxReconnectAttempts: Int
        
        public init(
            poolHost: String,
            poolPort: Int,
            useTLS: Bool = true,
            workerName: String,
            password: String = "x",
            maxHashrate: Double = 0, // 0 pour illimité
            autoReconnect: Bool = true,
            maxReconnectAttempts: Int = 5
        ) {
            self.poolHost = poolHost
            self.poolPort = poolPort
            self.useTLS = useTLS
            self.workerName = workerName
            self.password = password
            self.maxHashrate = maxHashrate
            self.autoReconnect = autoReconnect
            self.maxReconnectAttempts = maxReconnectAttempts
        }
    }
    
    // MARK: - Propriétés
    
    /// Configuration actuelle
    public private(set) var configuration: Configuration
    
    /// Client Stratum sous-jacent (préfixé par _ pour éviter les conflits avec les méthodes du protocole)
    private var __stratumClient: StratumClientNIO?
    
    /// État actuel du gestionnaire
    @Published public private(set) var state: State = State.stopped
    
    /// Statistiques de minage
    @Published public private(set) var stats = MiningStats()
    
    /// Délégé pour les événements de minage
    public weak var delegate: MiningManagerDelegate?
    
    // Gestionnaires de stratégies
    private var strategy: MiningStrategy
    private let strategyQueue = DispatchQueue(label: "com.m1miner.mining-strategy", qos: .userInitiated)
    
    // Journalisation
    private let logger: Logger
    
    // Gestion des erreurs
    private var errorHandler: ((Error) -> Void)?
    
    // Suivi des reconnexions
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    
    // MARK: - Initialisation
    
    /// Initialise un nouveau gestionnaire de minage
    /// - Parameter configuration: Configuration du gestionnaire
    public init(configuration: Configuration) {
        self.configuration = configuration
        self.strategy = DefaultMiningStrategy()
        
        // Configuration du logger
        var logger = Logger(label: "MiningManager")
        logger[metadataKey: "worker"] = "\(configuration.workerName)"
        self.logger = logger
        
        setupErrorHandling()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Contrôle du minage
    
    /// Démarre le processus de minage
    public func start() async throws {
        guard state != State.running && state != .starting else {
            self.logger.info("Démarrage ignoré - déjà en cours d'exécution")
            return
        }
        
        self.logger.info("Démarrage du gestionnaire de minage")
        state = .starting
        
        // Créer et configurer le client Stratum
        let client = StratumClientNIO(logger: logger)
        
        // Configurer les gestionnaires d'événements
        client.delegate = self
        self.__stratumClient = client
        
        // Démarrer la connexion
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                client.connect(host: configuration.poolHost, port: configuration.poolPort) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.self.logger.info("Connexion au pool réussie")
                        self.state = State.running
                        self.reconnectAttempts = 0
                        self.self.logger.info("Minage démarré avec succès")
                        
                        // Notifier le délégué
                        _Concurrency.Task {
                            await MainActor.run {
                                self.delegate?.miningManager(self, didChangeState: State.running)
                            }
                            continuation.resume()
                        }
                        
                    case .failure(let error):
                        self.self.logger.error("Échec de la connexion: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Démarrer la stratégie de minage
            await startMiningStrategy()
            
        } catch {
            self.state = .error(error)
            self.self.logger.error("Échec du démarrage: \(error.localizedDescription)")
            
            // Notifier le délégué
            await MainActor.run {
                self.delegate?.miningManager(self, didEncounterError: error)
                self.delegate?.miningManager(self, didChangeState: .error(error))
            }
            
            throw error
        }
    }
    
    /// Arrête le processus de minage
    public func stop() {
        guard state == State.running || state == .starting else { return }
        
        self.logger.info("Arrêt du gestionnaire de minage")
        state = .stopping
        
        // Arrêter la stratégie de minage
        _Concurrency.Task {
            await stopMiningStrategy()
            
            // Fermer la connexion
            await MainActor.run {
                self.__stratumClient?.disconnect()
                self.__stratumClient = nil
                self.state = State.stopped
                self.self.logger.info("Minage arrêté")
                self.delegate?.miningManager(self, didChangeState: State.stopped)
            }
        }
    }
    
    /// Met à jour la configuration du gestionnaire
    /// - Parameter newConfig: Nouvelle configuration
    public func updateConfiguration(_ newConfig: Configuration) async {
        let wasRunning = (state == State.running)
        
        if wasRunning {
            await MainActor.run {
                self.stop()
            }
        }
        
        // Mettre à jour la configuration
        configuration = newConfig
        
        if wasRunning {
            do {
                try await start()
            } catch {
                self.logger.error("Impossible de redémarrer après la mise à jour de la configuration: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Gestion des stratégies
    
    /// Définit une nouvelle stratégie de minage
    /// - Parameter strategy: Nouvelle stratégie à utiliser
    public func setMiningStrategy(_ strategy: MiningStrategy) {
        _Concurrency.Task {
            // Arrêter l'ancienne stratégie
            await strategy.stop()
            
            // Mettre à jour la stratégie sur la file d'attente principale
            await MainActor.run {
                self.strategy = strategy
            }
            
            // Démarrer la nouvelle stratégie si nous sommes en cours d'exécution
            if await state == State.running {
                await startMiningStrategy()
            }
        }
    }
    
    // MARK: - Méthodes privées
    
    private func setupErrorHandling() {
        errorHandler = { [weak self] error in
            guard let self = self else { return }
            
            self.self.logger.error("Erreur de minage: \(error.localizedDescription)")
            
            // Mettre à jour l'état
            self.state = .error(error)
            
            // Notifier le délégué sur le thread principal
            DispatchQueue.main.async {
                self.delegate?.miningManager(self, didEncounterError: error)
                self.delegate?.miningManager(self, didChangeState: .error(error))
            }
            
            // Tenter une reconnexion si nécessaire
            if self.configuration.autoReconnect && self.reconnectAttempts < self.configuration.maxReconnectAttempts {
                self.scheduleReconnect()
            }
        }
    }
    
    private func scheduleReconnect() {
        // Annuler toute tentative de reconnexion en attente
        reconnectTimer?.invalidate()
        
        // Calculer le délai avant la prochaine tentative (backoff exponentiel)
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0) // Maximum 60 secondes
        reconnectAttempts += 1
        
        self.logger.notice("Tentative de reconnexion \(reconnectAttempts)/\(configuration.maxReconnectAttempts) dans \(Int(delay)) secondes...")
        
        // Planifier la reconnexion
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            _Concurrency.Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    try await self.start()
                } catch {
                    self.self.logger.error("Échec de la reconnexion: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startMiningStrategy() async {
        guard let client = __stratumClient else { return }
        do {
            try await strategy.start(
                client: client,
                delegate: self,
                logger: logger
            )
        } catch {
            self.logger.error("Échec du démarrage de la stratégie: \(error.localizedDescription)")
            errorHandler?(error)
        }
    }
    
    private func stopMiningStrategy() {
        // Arrêter la stratégie de manière synchrone
        strategy.stop()
    }
}

import M1MinerShared

extension MiningManager: StratumClientDelegate {
    // MARK: - StratumClientDelegate

    public func stratumClient(_ client: StratumClientInterface, didChangeConnectionState isConnected: Bool) {
        self.logger.info("Changement d'état de connexion: \(isConnected)")
    }

    public func stratumClient(_ client: StratumClientInterface, didConnectToHost host: String, port: Int) {
        self.logger.info("Connecté au serveur \(host):\(port)")
    }

    public func stratumClient(_ client: StratumClientInterface, didUpdateDifficulty difficulty: Double) {
        self.logger.info("Difficulté mise à jour: \(difficulty)")
    }
    
    public func stratumClient(_ client: StratumClientInterface, didReceiveNotification notification: String, params: [Any]) {
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didReceiveNotification: notification, params: params)
            }
        }
    }

    public func stratumClient(_ client: StratumClientInterface, didReceiveJob job: StratumJob) {
        self.self.logger.debug("Nouveau travail reçu: job_id=\(job.jobId), nBits=\(job.nBits), clean_jobs=\(job.cleanJobs)")
        // Mettre à jour les statistiques
        self.stats.jobsReceived += 1
        self.stats.lastJobTime = Date()
        // Notifier la stratégie
        _Concurrency.Task {
            await self.strategy.handleNewJob(job)
        }
        // Notifier le délégué
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didReceiveJob: job)
            }
        }
    }

    public func stratumClient(_ client: StratumClientInterface, didSubmitResult result: SubmitResult) {
        // Mettre à jour les statistiques
        if result.accepted {
            self.stats.sharesAccepted += 1
            self.stats.lastShareTime = Date()
            if let difficulty = result.difficulty, difficulty > 0 {
                self.stats.totalDifficulty += difficulty
            }
            let metadata: [String: Logger.MetadataValue] = [
                "job_id": .string(result.jobId),
                "total_accepted": .stringConvertible(self.stats.sharesAccepted)
            ]
            self.self.logger.info("Partage accepté", metadata: metadata)
        } else {
            self.stats.sharesRejected += 1
            let metadata: [String: Logger.MetadataValue] = [
                "job_id": .string(result.jobId),
                "reason": .string(result.message ?? "Raison inconnue")
            ]
            self.self.logger.warning("Partage rejeté", metadata: metadata)
        }
        // Notifier le délégué
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didSubmitResult: result)
            }
        }
    }

    public func stratumClient(_ client: StratumClientInterface, didUpdateStats stats: ConnectionStats) {
        // Mapping complet des propriétés ConnectionStats -> MiningStats
        self.stats.connectionTime = stats.connectionDuration
        // self.stats.averageLatency = stats.networkLatency // Désactivé, propriété absente dans ConnectionStats
        self.stats.currentDifficulty = stats.difficulty
        self.stats.jobsReceived = stats.jobsReceived
        self.stats.sharesAccepted = stats.acceptedShares
        self.stats.sharesRejected = stats.rejectedShares
        self.stats.currentHashrate = stats.hashrate
        self.stats.lastShareTime = stats.lastShareTime
        // Si d'autres propriétés sont pertinentes, les ajouter ici
        // Par exemple :
        // self.stats.totalDifficulty = ...
        // self.stats.errors = ...
        // self.stats.lastJobTime = ...
        // Notifier le délégué
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didUpdateStats: self.stats)
            }
        }
    }

    public func stratumClient(_ client: StratumClientInterface, didReceiveError error: Error) {
        self.logger.error("Erreur du client Stratum: \(error.localizedDescription)")
        
        // Mettre à jour les statistiques
        stats.errors += 1
        
        // Notifier le délégué
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didEncounterError: error)
            }
        }
        
        // Gérer l'erreur
        errorHandler?(error)
        
        // Si nous étions en cours d'exécution et que la reconnexion automatique est activée
        if state == State.running && configuration.autoReconnect {
            scheduleReconnect()
        }
    }

    public func stratumClientDidDisconnect(_ client: StratumClientInterface, error: Error?) {
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManagerDidDisconnect(self)
            }
        }
        // Gérer la reconnexion si besoin...
    }
}

extension MiningManager: MiningStrategyDelegate {
    public func miningStrategy(_ strategy: MiningStrategy, didFindShare share: Share) {
        // Mettre à jour les statistiques
        stats.sharesSubmitted += 1
        
        // Soumettre la solution au pool
        _Concurrency.Task {
            do {
                guard let client = self.__stratumClient else {
                    throw MineringError.clientNotConnected
                }
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    client.submit(
                        worker: self.configuration.workerName,
                        jobId: share.jobId,
                        nonce: share.nonce,
                        result: share.extranonce2, // Note: Vérifier si c'est le bon champ pour le résultat
                        completion: { result in
                            switch result {
                            case .success(let accepted):
                                // Mettre à jour les statistiques
                                if accepted {
                                    self.stats.sharesAccepted += 1
                                    self.stats.lastShareTime = Date()
                                } else {
                                    self.stats.sharesRejected += 1
                                }
                                continuation.resume()
                                
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    )
                }
                
                // Le résultat sera traité par le delegate du client Stratum
                self.logger.debug("Partage soumis avec succès", metadata: [
                    "job_id": .string(share.jobId),
                    "nonce": .string(share.nonce)
                ])
                
            } catch {
                self.logger.error("Échec de la soumission du partage: \(error.localizedDescription)")
                
                // Notifier le délégué
                await MainActor.run {
                    self.delegate?.miningManager(self, didFailToSubmitShare: share, error: error)
                }
            }
        }
    }
    
    public func miningStrategy(_ strategy: MiningStrategy, didUpdateHashrate hashrate: Double) {
        // Mettre à jour les statistiques
        stats.currentHashrate = hashrate
        
        // Mettre à jour la moyenne mobile du hashrate
        stats.updateHashrateAverage(hashrate)
        
        // Notifier le délégué
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didUpdateHashrate: hashrate)
            }
        }
    }
    
    public func miningStrategy(_ strategy: MiningStrategy, didEncounterError error: Error) {
        self.logger.error("Erreur de la stratégie de minage: \(error.localizedDescription)")
        
        // Mettre à jour les statistiques
        stats.errors += 1
        
        // Notifier le délégué
        _Concurrency.Task {
            await MainActor.run {
                self.delegate?.miningManager(self, didEncounterError: error)
            }
        }
    }
}

// MARK: - Types associés

/// Protocole pour les délégués du gestionnaire de minage
public protocol MiningManagerDelegate: AnyObject {
    /// Appelé lorsque l'état du gestionnaire change
    func miningManager(_ manager: MiningManager, didChangeState state: MiningManager.State)
    
    /// Appelé lorsqu'une erreur se produit
    func miningManager(_ manager: MiningManager, didEncounterError error: Error)
    
    /// Appelé lorsque l'état de la connexion change
    func miningManager(_ manager: MiningManager, didChangeConnectionState isConnected: Bool)
    
    /// Appelé lorsque la connexion est perdue
    func miningManagerDidDisconnect(_ manager: MiningManager)
    
    /// Appelé lorsqu'un nouveau travail est reçu
    func miningManager(_ manager: MiningManager, didReceiveJob job: StratumJob)
    
    /// Appelé lorsqu'un résultat de soumission est reçu
    func miningManager(_ manager: MiningManager, didSubmitResult result: SubmitResult)
    
    /// Appelé lorsqu'un partage est trouvé mais n'a pas pu être soumis
    func miningManager(_ manager: MiningManager, didFailToSubmitShare share: Share, error: Error)
    
    /// Appelé lorsque la difficulté est mise à jour
    func miningManager(_ manager: MiningManager, didUpdateDifficulty difficulty: Double)
    
    /// Appelé lorsque le taux de hachage est mis à jour
    func miningManager(_ manager: MiningManager, didUpdateHashrate hashrate: Double)
    
    /// Appelé lorsque les statistiques sont mises à jour
    func miningManager(_ manager: MiningManager, didUpdateStats stats: MiningStats)
    
    /// Appelé lorsqu'une notification est reçue du serveur
    func miningManager(_ manager: MiningManager, didReceiveNotification method: String, params: [Any])
}

/// Extension pour rendre les méthodes optionnelles

public extension MiningManagerDelegate {
    func miningManager(_ manager: MiningManager, didChangeState state: MiningManager.State) {}
    func miningManager(_ manager: MiningManager, didEncounterError error: Error) {}
    func miningManager(_ manager: MiningManager, didChangeConnectionState isConnected: Bool) {}
    func miningManagerDidDisconnect(_ manager: MiningManager) {}
    func miningManager(_ manager: MiningManager, didReceiveJob job: StratumJob) {}
    func miningManager(_ manager: MiningManager, didSubmitResult result: SubmitResult) {}
    func miningManager(_ manager: MiningManager, didFailToSubmitShare share: Share, error: Error) {}
    func miningManager(_ manager: MiningManager, didUpdateDifficulty difficulty: Double) {}
    func miningManager(_ manager: MiningManager, didUpdateHashrate hashrate: Double) {}
    func miningManager(_ manager: MiningManager, didUpdateStats stats: MiningStats) {}
    func miningManager(_ manager: MiningManager, didReceiveNotification method: String, params: [Any]) {}
}

/// Statistiques de minage

public struct MiningStats {
    /// Temps de connexion total en secondes
    public internal(set) var connectionTime: TimeInterval = 0
    
    /// Taux de hachage actuel en H/s
    public internal(set) var currentHashrate: Double = 0
    
    /// Taux de hachage moyen (moyenne mobile) en H/s
    public internal(set) var averageHashrate: Double = 0
    
    /// Difficulté actuelle
    public internal(set) var currentDifficulty: Double = 0
    
    /// Difficulté totale des actions acceptées
    public internal(set) var totalDifficulty: Double = 0
    
    /// Nombre total de travaux reçus
    public internal(set) var jobsReceived: Int = 0
    
    /// Nombre total de parts soumises
    public internal(set) var sharesSubmitted: Int = 0
    
    /// Nombre de parts acceptées
    public internal(set) var sharesAccepted: Int = 0
    
    /// Nombre de parts rejetées
    public internal(set) var sharesRejected: Int = 0
    
    /// Taux de rejet en pourcentage
    public var rejectRate: Double {
        guard sharesSubmitted > 0 else { return 0 }
        return Double(sharesRejected) / Double(sharesSubmitted) * 100.0
    }
    
    /// Temps du dernier travail reçu
    public internal(set) var lastJobTime: Date?
    
    /// Temps de la dernière part acceptée
    public internal(set) var lastShareTime: Date?
    
    /// Temps écoulé depuis le dernier travail en secondes
    public var timeSinceLastJob: TimeInterval? {
        lastJobTime.map { -$0.timeIntervalSinceNow }
    }
    
    /// Temps écoulé depuis la dernière part acceptée en secondes
    public var timeSinceLastShare: TimeInterval? {
        lastShareTime.map { -$0.timeIntervalSinceNow }
    }
    
    /// Latence moyenne du réseau en secondes
    public internal(set) var averageLatency: TimeInterval = 0
    
    /// Nombre total d'erreurs
    public internal(set) var errors: Int = 0
    
    /// Historique des taux de hachage pour le calcul de la moyenne mobile
    private var hashrateHistory: [Double] = []
    private let maxHashrateHistory = 60 // Nombre d'échantillons à conserver
    
    /// Met à jour la moyenne mobile du taux de hachage
    mutating func updateHashrateAverage(_ hashrate: Double) {
        // Ajouter le nouveau taux de hachage à l'historique
        hashrateHistory.append(hashrate)
        
        // Limiter la taille de l'historique
        if hashrateHistory.count > maxHashrateHistory {
            hashrateHistory.removeFirst(hashrateHistory.count - maxHashrateHistory)
        }
        
        // Calculer la moyenne
        averageHashrate = hashrateHistory.reduce(0, +) / Double(hashrateHistory.count)
    }
    
    /// Réinitialise toutes les statistiques
    mutating func reset() {
        self = MiningStats()
    }
}

/// Erreurs liées au minage

public enum MineringError: LocalizedError {
    case clientNotConnected
    case invalidJob
    case submissionFailed(String)
    case maxReconnectAttemptsReached
    case invalidState
    case strategyError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .clientNotConnected:
            return "Le client Stratum n'est pas connecté"
        case .invalidJob:
            return "Travail de minage invalide"
        case .submissionFailed(let reason):
            return "Échec de la soumission: \(reason)"
        case .maxReconnectAttemptsReached:
            return "Nombre maximum de tentatives de reconnexion atteint"
        case .invalidState:
            return "État du gestionnaire invalide pour cette opération"
        case .strategyError(let error):
            return "Erreur de stratégie: \(error.localizedDescription)"
        }
    }
}
