import Metal
import MetalKit
import Foundation
import NIO
import NIOConcurrencyHelpers
import Dispatch
import NIOExtras
import Logging
import M1MinerShared
import M1MinerCore
import StratumClientNIO

public class Miner: @unchecked Sendable {
    // Propriétés d'état nécessaires pour la compilation et le fonctionnement


    
    // Logger pour le suivi des événements
    private let logger: Logger
    // Configuration du mineur
    private let config: MinerConfig // ⚠️ Doit être Sendable
    
    private var threadManager: ThreadManager
    private var stratumClient: StratumClientNIO?
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    // --- Metal ---
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipeline: MTLComputePipelineState?
    
    // MARK: - Propriétés publiques
    
    /// Indique si le mineur est en cours d'exécution
    public private(set) var isMining = false
    
    /// Travail de minage actuel
    public private(set) var currentJob: StratumJob?
    
    /// Indique si le mineur est connecté au pool
    public private(set) var isConnected = false
    
    /// Nonce actuel pour le hachage
    public private(set) var currentNonce: UInt32 = 0
    
    /// Nombre de parts acceptées par le pool
    public private(set) var sharesAccepted: Int = 0
    
    /// Nombre de parts rejetées par le pool
    public private(set) var sharesRejected: Int = 0
    
    /// Taux de hachage actuel en H/s
    public private(set) var hashrate: Double = 0.0
    
    /// Difficulté actuelle du travail de minage
    public private(set) var currentDifficulty: Double = 1.0
    
    /// Nombre total de hachages effectués
    public private(set) var hashCount: Int = 0
    private var lastHashTime: Date = Date()
    private var lastHashCount: Int = 0
    
    // Propriétés pour le suivi de l'état de la connexion
    private var connectionUptime: TimeInterval = 0.0
    private var validSharesCount: Int = 0
    private var invalidSharesCount: Int = 0
    private var currentHashrate: Double = 0.0
    
    // File d'attente pour les travaux de minage
    private let miningQueue = DispatchQueue(label: "com.m1miner.mining", qos: .userInitiated)
    
    // Verrou pour l'accès thread-safe à l'état partagé
    private let stateLock = NSLock()
    
    public init(config: MinerConfig) {
        // Initialiser le logger
        var logger = Logger(label: "com.m1miner.miner")
        logger.logLevel = .info
        self.logger = logger
        
        // Initialiser les propriétés stockées
        self.config = config
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.threadManager = ThreadManager()
        
        // Configurer Metal et le client Stratum
        self.metalDevice = MTLCreateSystemDefaultDevice()
        self.commandQueue = metalDevice?.makeCommandQueue()
        
        // Extraire les composants de l'URL du pool
        guard let url = URL(string: config.poolUrl),
              let host = url.host,
              let port = url.port else {
            fatalError("URL du pool invalide: \(config.poolUrl)")
        }
        
        let useTLS = url.scheme?.lowercased() == "stratum+ssl" || url.scheme?.lowercased() == "stratum+tls"
        
        // Créer le client Stratum avec le logger
        Swift.print("🛠  Création du client Stratum...")
        self.stratumClient = StratumClientNIO(logger: Logger(label: "M1Miner.StratumClient"))
        
        // Configurer le délégué
        self.stratumClient?.delegate = self
        
        // Se connecter au pool
        Swift.print("🚀 Connexion au pool...")
        self.stratumClient?.connect(
            host: host,
            port: port,
            useTLS: useTLS,
            workerName: config.workerName,
            password: config.password
        ) { result in
            switch result {
            case .success:
                Swift.print("✅ Connecté avec succès au pool")
            case .failure(let error):
                Swift.print("❌ Échec de la connexion au pool: \(error)")
            }
        }
        
        // Configurer les shaders et le pipeline Metal
        setupShaders()
    }
    
    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    /// Configure l'environnement Metal
    private func setupMetal() {
        // Vérifier si Metal est disponible
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal n'est pas disponible sur cet appareil")
        }
        
        self.metalDevice = device
        self.commandQueue = device.makeCommandQueue()
        
        // Configurer les shaders
        setupShaders()
    }
    
    private func setupStratumClient() {
        // Cette méthode est maintenant intégrée dans l'initialiseur principal
        // pour éviter la duplication de code et les problèmes de concurrence
    
    }
    
    /// Charge et configure les shaders Metal en fonction de l'algorithme sélectionné
    private func setupShaders() {
        // Vérifier que nous avons un périphérique Metal valide
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("❌ Votre appareil ne prend pas en charge Metal")
        }
        
        self.metalDevice = device
        Swift.print("✅ Périphérique Metal détecté: \(device.name)")
        
        // Déterminer le fichier de shader à charger en fonction de l'algorithme
        let shaderFile: String
        switch config.algorithm.lowercased() {
        case "btg", "equihash":
            shaderFile = "Equihash.metal"
        case "kawpow":
            shaderFile = "KawPow.metal"
        default:
            shaderFile = "Equihash.metal" // Par défaut
        }
        
        // Obtenir le chemin du bundle contenant les ressources
        let bundlePath = Bundle.main.bundlePath
        let resourcesPath = (bundlePath as NSString).appendingPathComponent("Contents/Resources/Shaders")
        let shaderPath = (resourcesPath as NSString).appendingPathComponent(shaderFile)
        Swift.print("🔍 Chargement du shader depuis: \(shaderPath)")
        
        // Charger le contenu du fichier de shader
        let shaderSource: String
        if let source = try? String(contentsOfFile: shaderPath, encoding: .utf8) {
            shaderSource = source
        } else {
            // Si le chargement échoue, essayer avec le chemin direct pour le débogage
            let debugPath = "/Users/selim/Desktop/M1Miner/Sources/Resources/Shaders/\(shaderFile)"
            Swift.print("⚠️ Impossible de charger depuis le bundle, tentative avec le chemin de débogage: \(debugPath)")
            
            guard let debugShaderSource = try? String(contentsOfFile: debugPath, encoding: .utf8) else {
                fatalError("❌ Impossible de lire le fichier de shader depuis aucun des chemins\n1. \(shaderPath)\n2. \(debugPath)")
            }
            Swift.print("⚠️ Chargement réussi depuis le chemin de débogage")
            shaderSource = debugShaderSource
        }
        
        // Créer la bibliothèque à partir du code source
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
            Swift.print("✅ Shader chargé avec succès: \(shaderFile)")
        } catch {
            fatalError("❌ Erreur lors de la compilation du shader: \(error)")
        }
        
        // Déterminer la fonction de hachage à utiliser en fonction de l'algorithme
        let functionName: String
        switch config.algorithm.lowercased() {
        case "btg", "equihash":
            functionName = "equihash_144_5"
            Swift.print("🔧 Utilisation de l'algorithme Equihash (144,5) pour Bitcoin Gold")
            
        case "kawpow":
            functionName = "kawpow_hash"
            Swift.print("🔧 Utilisation de l'algorithme KawPoW")
            
        case "ghostrider":
            fallthrough
            
        default:
            functionName = "ghostrider_hash"
            Swift.print("🔧 Utilisation de l'algorithme GhostRider (par défaut)")
        }
        
        // Charger la fonction de calcul
        guard let computeFunction = library.makeFunction(name: functionName) else {
            fatalError("Impossible de charger la fonction \(functionName)")
        }
        
        // Créer le pipeline de calcul
        do {
            self.computePipeline = try device.makeComputePipelineState(function: computeFunction)
            Swift.print("✅ Pipeline de calcul initialisé avec succès pour l'algorithme: \(config.algorithm)")
        } catch {
            fatalError("Erreur lors de la création du pipeline de calcul: \(error)")
        }
    }
    
    // MARK: - Configuration
    
    // MARK: - Gestion de la connexion
    
    private func connectToPool(completion: @escaping (Bool) -> Void) {
        Swift.print("🔗 Tentative de connexion au pool...")
        Swift.print("   - URL du pool: \(config.poolUrl)")
        
        // Valider l'URL du pool
        guard let url = URL(string: config.poolUrl) else {
            let error = "URL du pool invalide: \(config.poolUrl)"
            Swift.print("❌ \(error)")
            
            completion(false)
            return
        }
        
        // Extraire les composants de l'URL
        guard let host = url.host, let port = url.port else {
            let error = "Impossible d'extraire l'hôte et le port de l'URL du pool: \(config.poolUrl)"
            Swift.print("❌ \(error)")
            
            completion(false)
            return
        }
        
        let useTLS = url.scheme?.lowercased() == "stratum+ssl" || url.scheme?.lowercased() == "stratum+tls"
        let workerName = config.workerName
        let password = config.password ?? "x"
        
        Swift.print("""
        🔧 Configuration de la connexion:
           - Hôte: \(host)
           - Port: \(port)
           - TLS: \(useTLS ? "Activé" : "Désactivé")
           - Worker: \(workerName)
        """)
        
        // Créer le client Stratum avec le logger
        Swift.print("🛠  Création du client Stratum...")
        stratumClient = StratumClientNIO(logger: Logger(label: "M1Miner.StratumClient"))
        
        // Configurer les callbacks
        stratumClient?.delegate = self
        
        Swift.print("🚀 Démarrage de la connexion au pool...")
        let startTime = Date()
        
        // Se connecter au pool avec la configuration
        stratumClient?.connect(
            host: host,
            port: Int(port),
            useTLS: useTLS,
            workerName: workerName,
            password: password
        ) { [weak self] result in
            guard let self = self else { return }
            
            let duration = String(format: "%.2f", Date().timeIntervalSince(startTime))
            
            switch result {
            case .success():
                Swift.print("✅ Connecté avec succès au pool en \(duration)s")
                self.isConnected = true
                                completion(true)
                
            case .failure(let error):
                Swift.print("❌ Échec de la connexion après \(duration)s: \(error.localizedDescription)")
                                self.isConnected = false
                completion(false)
            }
        }
    }
    
    // MARK: - Gestion du minage
    
    /// Démarre le processus de minage
    public func start() {
        guard !isMining else { return }
        
        // Vérifier que nous avons une configuration valide
        guard config.isValid else {
            Swift.print("Erreur de configuration")
            return
        }
        
        // Vérifier que nous sommes connectés au pool
        guard isConnected else {
            connectToPool { [weak self] success in
                if success {
                    // démarrage du minage si nécessaire
                }
            }
            return
        }
        
        // startMining() // Méthode supprimée
    }
    
    /// Arrête le processus de minage
    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard isMining else { return }
        
        isMining = false
        Swift.print("\n⏹️ Mineur arrêté")
        Swift.print("📊 Statistiques finales:")
        Swift.print("   ✅ Parts acceptées: \(sharesAccepted)")
        Swift.print("   ❌ Parts rejetées: \(sharesRejected)")
        Swift.print("   ⚡ Hashrate final: \(String(format: "%.2f", hashrate)) H/s")
    }
    

    
    // MARK: - Boucle de minage
    
    /// Boucle principale de minage
    private func miningLoop() {
        Swift.print("⛏️  Démarrage de la boucle de minage...")
        
        // Démarrer le suivi du hashrate
        startHashrateMonitor()
        
        while isMining {
            do {
                // Vérifier si nous avons un travail en cours
                guard let job = currentJob else {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                
                // Exécuter le calcul de hachage
                try processJob(job)
                
                // Mettre à jour le compteur de hachages
                stateLock.lock()
                lastHashCount += 1
                stateLock.unlock()
                
            } catch {
                Swift.print("❌ Erreur lors du minage: \(error.localizedDescription)")
                Thread.sleep(forTimeInterval: 5) // Attendre avant de réessayer
            }
        }
        
        // Nettoyer les ressources
        stopHashrateMonitor()
    }
    
    /// Démarre le suivi du hashrate
    private func startHashrateMonitor() {
        // Mettre à jour le hashrate toutes les secondes
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isMining else { return }
            
            self.stateLock.lock()
            let now = Date()
            let timeElapsed = now.timeIntervalSince(self.lastHashTime)
            
            // Calculer le hashrate (haches par seconde)
            if timeElapsed > 0 {
                self.hashrate = Double(self.lastHashCount) / timeElapsed
                Swift.print("⚡ \(String(format: "%.2f", self.hashrate)) H/s")
                
                // Afficher les statistiques
                self.printStats()
            }
            
            // Réinitialiser les compteurs
            self.lastHashTime = now
            self.lastHashCount = 0
            self.stateLock.unlock()
        }
    }
    
    /// Arrête le suivi du hashrate
    private func stopHashrateMonitor() {
        // Pour l'instant, nous n'avons pas besoin de nettoyage spécifique
        // car le timer est fortement référencé par le run loop
    }
    
    /// Affiche les statistiques actuelles
    private func printStats() {
        // Utiliser des variables locales pour éviter les blocages
        let currentHashrate = hashrate
        let accepted = sharesAccepted
        let rejected = sharesRejected
        
        // Effacer la ligne précédente
        Swift.print("\r", terminator: "")
        
        // Afficher les statistiques
        Swift.print("⚡ \(String(format: "%6.2f", currentHashrate)) H/s | ", terminator: "")
        Swift.print("✅ \(accepted) | ", terminator: "")
        Swift.print("❌ \(rejected) | ", terminator: "")
        Swift.print("🧱 \(currentJob?.jobId.prefix(8) ?? "Aucun")", terminator: "")
        
        // S'assurer que la sortie est immédiatement affichée
        fflush(stdout)
    }
    
    // MARK: - Traitement des travaux
    
    /// Traite un travail de minage reçu du pool
    private func processJob(_ job: StratumJob) throws {
        // Vérifier que nous avons tout ce dont nous avons besoin
        guard let device = metalDevice,
              let commandQueue = commandQueue,
              let computePipeline = computePipeline else {
            throw MinerError.metalNotInitialized
        }
        
        // Préparer les données d'en-tête pour le hachage
        guard let headerData = job.headerData() else {
            throw MinerError.invalidJob
        }
        
        // Convertir la cible en données binaires
        guard let targetData = job.nBits.hexData else {
            throw MinerError.invalidJob
        }
        
        // Convertir la cible en valeur numérique pour la vérification
        let _ = targetData.withUnsafeBytes { $0.load(as: UInt256.self) } // targetValue non utilisée pour le moment
        
        // Créer les tampons de données pour le GPU
        var headerBytes = [UInt8](headerData)
        guard let headerBuffer = device.makeBuffer(bytes: &headerBytes,
                                                length: headerBytes.count,
                                                options: .storageModeShared),
              let nonceBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size,
                                               options: .storageModeShared) else {
            throw MinerError.bufferCreationFailed
        }
        
        // Essayer plusieurs nonces
        for _ in 0..<1000 {
            // Vérifier si nous devons arrêter
            stateLock.lock()
            let shouldContinue = isMining
            stateLock.unlock()
            
            if !shouldContinue { break }
            
            // Incrémenter le nonce
            currentNonce &+= 1
            
            // Copier le nonce dans le tampon
            let noncePtr = nonceBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
            noncePtr.pointee = currentNonce
            
            // Créer une commande
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw MinerError.commandCreationFailed
            }
            
            // Configurer le pipeline de calcul
            computeEncoder.setComputePipelineState(computePipeline)
            computeEncoder.setBuffer(headerBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(nonceBuffer, offset: 0, index: 1)
            
            // Calculer la taille des groupes de threads
            let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
            let threadgroupsPerGrid = MTLSize(width: 1, height: 1, depth: 1)
            
            // Lancer le calcul
            computeEncoder.dispatchThreadgroups(threadgroupsPerGrid,
                                             threadsPerThreadgroup: threadsPerThreadgroup)
            
            // Terminer l'encodage et exécuter
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            // Vérifier les résultats (simplifié pour l'exemple)
            // En réalité, il faudrait vérifier si le hachage résultant est inférieur à la cible
            
            // Simuler une solution trouvée occasionnellement
            if currentNonce % 1000 == 0 {
                // Soumettre la solution au pool
                submitSolution(job: job, nonce: currentNonce)
            }
        }
    }
    
    /// Soumet une solution au pool
    private func submitSolution(job: StratumJob, nonce: UInt32) {
        // Vérifier que nous avons un client Stratum valide
        guard let stratumClient = self.stratumClient else {
            Swift.print("Impossible de soumettre la solution: client Stratum non initialisé")
            return
        }
        
        // Convertir le nonce en format hexadécimal
        let nonceStr = String(format: "%08x", nonce).lowercased()
        
        // Pour l'instant, nous utilisons un résultat factice. Dans une implémentation réelle,
        // vous devrez calculer le hash réel de la solution.
        let result = "0000000000000000000000000000000000000000000000000000000000000000"
        
        Swift.print("Soumission de la solution: job_id=\(job.jobId), nonce=\(nonceStr)")
        
        // Soumettre la solution au pool via le client Stratum
        stratumClient.submit(
            worker: config.workerName,
            jobId: job.jobId,
            nonce: nonceStr,
            result: result
        ) { [weak self] submitResult in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch submitResult {
                case .success(let accepted):
                    self.stateLock.lock()
                    if accepted {
                        self.sharesAccepted += 1
                        Swift.print("✅ Part acceptée! (Total: \(self.sharesAccepted))")
                    } else {
                        self.sharesRejected += 1
                        Swift.print("❌ Part rejetée! (Total: \(self.sharesRejected))")
                    }
                    self.stateLock.unlock()
                    
                    // Mettre à jour l'interface utilisateur
                    
                case .failure(let error):
                    Swift.print("Erreur lors de la soumission: \(error.localizedDescription)")
                }
            }
        }
    }
    
}

// MARK: - StratumClientDelegate

extension Miner: StratumClientDelegate {
    // --- MÉTHODES REQUISES PAR LE PROTOCOLE ---
    
    public func stratumClient(_ client: StratumClientInterface, didChangeConnectionState isConnected: Bool) {
        // Implémentation ici si besoin (ex: notification UI)
    }
    
    public func stratumClient(_ client: StratumClientInterface, didConnectToHost host: String, port: Int) {
        // Implémentation ici si besoin
    }
    
    public func stratumClientDidDisconnect(_ client: StratumClientInterface, error: Error?) {
        // Implémentation ici si besoin
    }
    
    public func stratumClient(_ client: StratumClientInterface, didUpdateStats stats: ConnectionStats) {
        // Implémentation ici si besoin
    }
    
    public func stratumClient(_ client: StratumClientInterface, didReceiveError error: Error) {
        Swift.print("Erreur du client Stratum: \(error)")
    }

    public func stratumClient(_ client: StratumClientInterface, didUpdateDifficulty difficulty: Double) {
        // Implémentation ici si besoin (par exemple, stocker la difficulté courante ou notifier l'UI)
    }
    
    public func stratumClient(_ client: StratumClientInterface, didReceiveNotification notification: String, params: [Any]) {
        // Implémentation ici si besoin
    }
    
    public func stratumClient(_ client: StratumClientInterface, didReceiveJob job: StratumJob) {
        stateLock.lock()
        defer { stateLock.unlock() }
        // Si nous sommes en train de miner, démarrer le traitement du nouveau travail
        if isMining {
            do {
                try processJob(job)
            } catch {
                // Gestion d'erreur
            }
        }
    }
}

// MARK: - Types




// Implémentations par défaut pour les méthodes optionnelles



// Extension pour convertir une chaîne hexadécimale en Data

// Extension pour convertir une chaîne hexadécimale en Data
extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var i = hex.startIndex
        
        for _ in 0..<len {
            let j = hex.index(i, offsetBy: 2)
            let bytes = hex[i..<j]
            
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            
            i = j
        }
        
        self = data
    }
}
