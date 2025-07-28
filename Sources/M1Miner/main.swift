import Foundation
import NIO
import M1MinerCore
import Darwin

// MARK: - Variables globales pour la gestion des signaux

private var globalMiner: Miner?

// MARK: - Gestionnaires de signaux

private func handleSIGINT(_ signal: Int32) {
    print("\n🔔 Réception du signal d'arrêt (Ctrl+C). Arrêt en cours...")
    globalMiner?.stop()
}

private func handleSIGTERM(_ signal: Int32) {
    print("\n🔔 Réception du signal de terminaison. Arrêt en cours...")
    globalMiner?.stop()
}

// MARK: - Point d'entrée principal de l'application

// Définition du point d'entrée
let app = M1MinerApp()
app.run()

// Garder l'application en cours d'exécution
RunLoop.current.run()

// MARK: - Structure principale de l'application

class M1MinerApp {
    private var miner: Miner?
    
    func run() {
        print("🚀 Démarrage de M1Miner...")
        
        // Vérifier si le fichier de configuration existe
        let configPath = FileManager.default.currentDirectoryPath + "/config.json"
        guard FileManager.default.fileExists(atPath: configPath) else {
            print("❌ Erreur: Le fichier de configuration 'config.json' est introuvable.")
            print("ℹ️ Utilisez 'cp config.example.json config.json' pour créer un fichier de configuration.")
            exit(1)
        }
        
        do {
            // Initialiser le mineur
            let miner = try Miner()
            self.miner = miner
            globalMiner = miner // Stocker une référence globale pour les gestionnaires de signaux
            
            // Configurer les gestionnaires de signaux
            signal(SIGINT, handleSIGINT)
            signal(SIGTERM, handleSIGTERM)
            
            // Démarrer le mineur
            miner.run()
        } catch {
            print("❌ Erreur lors du démarrage du mineur: \(error)")
            exit(1)
        }
    }
}

// MARK: - Types et protocoles

// MARK: - Implémentation du mineur

class Miner {
    // MARK: - Propriétés
    
    private var isRunning = false
    private var config: MinerConfig!
    private var coreMiner: M1MinerCore.Miner?

    private var startTime = Date()
    private var lastPrintTime = Date()
    private var hashrates: [Double] = []
    
    // MARK: - Initialisation
    
    init() throws {
        try loadConfig()

    }
    
    // MARK: - Méthodes publiques
    
    func run() {
        print("⚙️  Configuration chargée")
        print("💰 Portefeuille: \(config.walletAddress)")
        print("⛏  Algorithme: \(config.algorithm)")
        
        startMining()
    }
    
    func stop() {
        print("\n🛑 Arrêt du mineur...")
        isRunning = false
        coreMiner?.stop()
        exit(0)
    }
    
    // MARK: - Méthodes privées
    
    private func loadConfig() throws {
        let configPath = FileManager.default.currentDirectoryPath + "/config.json"
        print("🔍 Chargement de la configuration depuis: \(configPath)")
        
        // Vérifier si le fichier existe
        if !FileManager.default.fileExists(atPath: configPath) {
            print("❌ Erreur: Le fichier de configuration n'existe pas à l'emplacement: \(configPath)")
            throw NSError(domain: "M1Miner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fichier de configuration introuvable"])
        }
        
        // Lire le contenu du fichier
        print("📄 Lecture du fichier de configuration...")
        let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
        
        // Afficher le contenu brut pour le débogage
        if let configString = String(data: configData, encoding: .utf8) {
            print("📋 Contenu du fichier config.json:\n\(configString)")
        } else {
            print("⚠️ Impossible de lire le contenu du fichier de configuration comme texte UTF-8")
        }
        
        // Décoder la configuration
        print("🔧 Décodage de la configuration...")
        let decoder = JSONDecoder()
        self.config = try decoder.decode(MinerConfig.self, from: configData)
        
        // Afficher les paramètres importants de la configuration
        print("✅ Configuration chargée avec succès:")
        print("   - Pool URL: \(self.config.poolUrl)")
        print("   - Adresse du portefeuille: \(self.config.walletAddress)")
        print("   - Algorithme: \(self.config.algorithm)")
        print("   - Intensité: \(self.config.intensity)")
        print("   - Threads: \(self.config.threads)")
    }
    
    private func startMining() {
        print("⛏ Démarrage du minage...")
        
        // Initialisation du mineur
        coreMiner = M1MinerCore.Miner(config: config)

        
        coreMiner?.start()
        isRunning = true
        
        print("✅ Mineur démarré avec succès")
        print("📊 Appuyez sur Ctrl+C pour arrêter")
    }
    
    func updateHashrate(_ hashrate: Double) {
        // Mettre à jour la moyenne mobile des hashrates
        hashrates.append(hashrate)
        if hashrates.count > 60 { // Garder les 60 dernières secondes
            hashrates.removeFirst()
        }
        
        let now = Date()
        if now.timeIntervalSince(lastPrintTime) >= 30 { // Afficher toutes les 30 secondes
            let avgHashrate = hashrates.average
            let uptime = Int(now.timeIntervalSince(startTime))
            let hours = uptime / 3600
            let minutes = (uptime % 3600) / 60
            let seconds = uptime % 60
            
            print("[📊 \(String(format: "%.2f MH/s", avgHashrate))] [⏱ \(String(format: "%02d:%02d:%02d", hours, minutes, seconds))]")
            lastPrintTime = now
        }
    }
    
    func updateMonitorReport(_ report: MinerMonitor.Report) {
        // Mettre à jour le hashrate à partir du rapport
        updateHashrate(report.hashrate)
        
        // Afficher les statistiques en mode debug
        #if DEBUG
        let hashrateStr: String
        if report.hashrate > 1_000_000 {
            hashrateStr = String(format: "%.2f MH/s", report.hashrate / 1_000_000)
        } else if report.hashrate > 1_000 {
            hashrateStr = String(format: "%.2f kH/s", report.hashrate / 1_000)
        } else {
            hashrateStr = "\(Int(report.hashrate)) H/s"
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        let uptime = formatter.string(from: report.uptime) ?? "0s"
        
        print("""
        📊 Rapport de surveillance:
        - ⚡ Hashrate: \(hashrateStr)
        - ⏱️  Uptime: \(uptime)
        - 📦 Hashs totaux: \(report.totalHashes.formatted())
        - ✅ Parts acceptées: \(report.sharesAccepted) (+\(report.newSharesAccepted))
        - ❌ Parts rejetées: \(report.sharesRejected) (+\(report.newSharesRejected))
        - 📉 Taux de rejet: \(String(format: "%.1f%%", report.shareRejectRate * 100))
        - 💻 Charge système: \(String(format: "%.1f%%", report.systemLoad * 100))
        """)
        #endif
    }
}

// MARK: - Implémentation des delegates

func stratumClient(_ client: M1MinerCore.Miner, didUpdateDifficulty difficulty: Double) {
    print("📊 Difficulté mise à jour: \(String(format: "%.2f", difficulty))")
}

// Extension pour calculer la moyenne d'un tableau de Double
extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
