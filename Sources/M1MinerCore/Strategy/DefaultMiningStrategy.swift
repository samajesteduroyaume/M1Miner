import Foundation
import StratumClientNIO
import Logging
import M1MinerShared

/// Stratégie de minage par défaut qui implémente le protocole MiningStrategy
public final class DefaultMiningStrategy: MiningStrategy {
    // MARK: - Propriétés
    
    /// Délégé pour les événements de la stratégie
    public weak var delegate: MiningStrategyDelegate?
    
    /// Client Stratum pour la communication avec le pool
    private weak var client: StratumClientNIO?
    
    /// Travail de minage actuel
    private var currentJob: StratumJob?
    
    /// File d'attente pour le traitement des travaux
    private let queue = DispatchQueue(label: "com.m1miner.strategy.default", qos: .userInitiated)
    
    /// Indique si la stratégie est en cours d'exécution
    private var isRunning = false
    
    /// Compteur de hachage pour le calcul du taux de hachage
    private var hashCounter: UInt64 = 0
    private var lastHashRateUpdate = Date()
    
    /// Minuteur pour la mise à jour du taux de hachage
    private var hashRateTimer: Timer?
    
    /// Journalisation
    private var logger: Logger
    
    // MARK: - Initialisation
    
    public init() {
        self.logger = Logger(label: "DefaultMiningStrategy")
        
        // Configurer le minuteur de mise à jour du taux de hachage
        setupHashRateTimer()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Configuration du minuteur de taux de hachage
    
    private func setupHashRateTimer() {
        // Mettre à jour le taux de hachage toutes les secondes
        hashRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateHashRate()
        }
    }
    
    private func updateHashRate() {
        // Calculer le taux de hachage (hachages par seconde)
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastHashRateUpdate)
        
        guard timeElapsed > 0 else { return }
        
        let hashesPerSecond = Double(hashCounter) / timeElapsed
        
        // Réinitialiser le compteur et l'horodatage
        hashCounter = 0
        lastHashRateUpdate = now
        
        // Informer le délégué du nouveau taux de hachage
        delegate?.miningStrategy(self, didUpdateHashrate: hashesPerSecond)
    }
    
    // MARK: - MiningStrategy
    
    public func start(client: StratumClientNIO, delegate: MiningStrategyDelegate, logger: Logger) async throws {
        self.client = client
        self.delegate = delegate
        self.logger = logger
        
        guard !isRunning else { return }
        
        logger.info("Démarrage de la stratégie de minage par défaut")
        isRunning = true
        
        // Démarrer le minuteur de taux de hachage s'il n'est pas déjà en cours
        if hashRateTimer == nil {
            setupHashRateTimer()
        }
        
        // Démarrer le traitement des travaux
        startMining()
    }
    
    public func stop() {
        guard isRunning else { return }
        
        logger.info("Arrêt de la stratégie de minage par défaut")
        isRunning = false
        
        // Arrêter le minuteur de taux de hachage
        hashRateTimer?.invalidate()
        hashRateTimer = nil
    }
    
    public func handleNewJob(_ job: StratumJob) async {
        // Créer une copie locale de la référence à self et du job
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                // Capturer self fortement pour la durée de l'exécution
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Créer une copie locale du job pour éviter les problèmes de concurrence
                let localJob = job
                self.processNewJob(localJob)
                continuation.resume()
            }
        }
    }
    
    // MARK: - Traitement des travaux
    
    private func processNewJob(_ job: StratumJob) {
        guard isRunning else { return }
        
        logger.debug("Nouveau travail reçu", metadata: ["job_id": .string(job.jobId)])
        
        // Mettre à jour le travail actuel
        currentJob = job
        
        // Pour cette implémentation de base, nous allons simplement soumettre un nonce aléatoire
        // pour démontrer le fonctionnement. Dans une implémentation réelle, vous implémenteriez
        // ici votre logique de minage (par exemple, en utilisant un algorithme de hachage spécifique).
        
        // Simuler un certain travail de minage
        let nonce = String(format: "%08x", arc4random())
        
        // Pour cette démonstration, nous supposons que le travail est valide 10% du temps
        let isShareValid = (arc4random() % 10) == 0
        
        if isShareValid, let currentJob = currentJob {
            // Créer un partage valide
            let share = Share(
                jobId: currentJob.jobId,
                extranonce2: "00000000", // Valeur factice pour la démo
                ntime: String(format: "%08x", UInt32(Date().timeIntervalSince1970)),
                nonce: nonce,
                difficulty: currentJob.difficulty
            )
            
            // Informer le délégué qu'un partage a été trouvé
            delegate?.miningStrategy(self, didFindShare: share)
        }
        
        // Incrémenter le compteur de hachage pour le calcul du taux de hachage
        hashCounter += 1
    }
    
    private func startMining() {
        // Démarrer une boucle de minage dans un thread séparé
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Capturer self fortement une seule fois au début
            guard let self = self else { return }
            
            // Créer une référence locale pour éviter de capturer self dans la boucle
            var shouldContinue = true
            
            while shouldContinue {
                // Utiliser un bloc de synchronisation pour accéder en toute sécurité à isRunning
                let isRunning = self.queue.sync { self.isRunning }
                
                // Mettre à jour la condition de boucle
                shouldContinue = isRunning
                
                if !shouldContinue {
                    break
                }
                
                // Si nous avons un travail en cours, le traiter
                let currentJob = self.queue.sync { self.currentJob }
                
                if let job = currentJob {
                    self.processNewJob(job)
                } else {
                    // Attendre brièvement avant de vérifier à nouveau
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                // Pour éviter une utilisation excessive du CPU
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
}

// MARK: - Protocole MiningStrategy

/// Protocole qui définit les méthodes requises pour une stratégie de minage personnalisée
public protocol MiningStrategy: AnyObject {
    /// Délégué pour les événements de la stratégie
    var delegate: MiningStrategyDelegate? { get set }
    
    /// Démarre la stratégie de minage
    /// - Parameters:
    ///   - client: Le client Stratum à utiliser pour la communication
    ///   - delegate: Le délégué pour recevoir les événements
    ///   - logger: Le logger à utiliser pour la journalisation
    func start(client: StratumClientNIO, delegate: MiningStrategyDelegate, logger: Logger) async throws
    
    /// Arrête la stratégie de minage
    func stop()
    
    /// Traite un nouveau travail de minage
    /// - Parameter job: Le travail de minage à traiter
    func handleNewJob(_ job: StratumJob) async
}

/// Délégué pour les événements de la stratégie de minage
public protocol MiningStrategyDelegate: AnyObject {
    /// Appelé lorsqu'un partage valide est trouvé
    /// - Parameters:
    ///   - strategy: La stratégie qui a trouvé le partage
    ///   - share: Les détails du partage
    func miningStrategy(_ strategy: MiningStrategy, didFindShare share: Share)
    
    /// Appelé lorsque le taux de hachage est mis à jour
    /// - Parameters:
    ///   - strategy: La stratégie qui a mis à jour le taux de hachage
    ///   - hashrate: Le nouveau taux de hachage en H/s
    func miningStrategy(_ strategy: MiningStrategy, didUpdateHashrate hashrate: Double)
    
    /// Appelé lorsqu'une erreur se produit dans la stratégie
    /// - Parameters:
    ///   - strategy: La stratégie qui a rencontré l'erreur
    ///   - error: L'erreur qui s'est produite
    func miningStrategy(_ strategy: MiningStrategy, didEncounterError error: Error)
}

// Extension pour rendre les méthodes optionnelles
public extension MiningStrategyDelegate {
    func miningStrategy(_ strategy: MiningStrategy, didFindShare share: Share) {}
    func miningStrategy(_ strategy: MiningStrategy, didUpdateHashrate hashrate: Double) {}
    func miningStrategy(_ strategy: MiningStrategy, didEncounterError error: Error) {}
}
