import Foundation

/// Classe de surveillance des performances et de la stabilité du mineur
public class MinerMonitor {
    // Référence au mineur à surveiller
    private weak var miner: Miner?
    
    // Configuration de la surveillance
    private let updateInterval: TimeInterval
    private var isMonitoring = false
    private var monitoringTask: Task<Void, Never>?
    
    // Statistiques
    private var startTime: Date = .distantPast
    private var lastUpdateTime: Date = .distantPast
    private var lastHashCount: Int = 0
    private var lastAcceptedShares: Int = 0
    private var lastRejectedShares: Int = 0
    
    // Délégé pour les rapports de surveillance
    public weak var delegate: MinerMonitorDelegate?
    
    /// Initialise un nouveau moniteur pour le mineur spécifié
    /// - Parameters:
    ///   - miner: Le mineur à surveiller
    ///   - updateInterval: Intervalle de mise à jour en secondes (par défaut: 10 secondes)
    public init(miner: Miner, updateInterval: TimeInterval = 10.0) {
        self.miner = miner
        self.updateInterval = updateInterval
    }
    
    /// Démarre la surveillance du mineur
    public func start() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        lastUpdateTime = startTime
        
        monitoringTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isMonitoring {
                await self.collectMetrics()
                try? await Task.sleep(nanoseconds: UInt64(self.updateInterval * 1_000_000_000))
            }
        }
        
        print("🔍 Surveillance démarrée (mise à jour toutes les \(updateInterval)s)")
    }
    
    /// Arrête la surveillance du mineur
    public func stop() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        
        print("🔍 Surveillance arrêtée")
    }
    
    /// Méthode appelée périodiquement pour collecter les métriques
    private func collectMetrics() async {
        guard let miner = self.miner else {
            self.stop()
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(startTime)
        
        // Récupérer les statistiques actuelles
        let currentHashCount = miner.hashCount
        let currentAccepted = miner.sharesAccepted
        let currentRejected = miner.sharesRejected
        
        // Calculer les différences depuis la dernière mise à jour
        let timeDiff = now.timeIntervalSince(lastUpdateTime)
        let hashDiff = currentHashCount - lastHashCount
        let acceptedDiff = currentAccepted - lastAcceptedShares
        let rejectedDiff = currentRejected - lastRejectedShares
        
        // Calculer le hashrate (haches par seconde)
        let hashrate = timeDiff > 0 ? Double(hashDiff) / timeDiff : 0
        
        // Mettre à jour les références
        lastUpdateTime = now
        lastHashCount = currentHashCount
        lastAcceptedShares = currentAccepted
        lastRejectedShares = currentRejected
        
        // Créer un rapport
        let report = MinerMonitor.Report(
            timestamp: now,
            uptime: elapsed,
            hashrate: hashrate,
            totalHashes: currentHashCount,
            sharesAccepted: currentAccepted,
            sharesRejected: currentRejected,
            newSharesAccepted: acceptedDiff,
            newSharesRejected: rejectedDiff,
            shareRejectRate: Double(rejectedDiff) / Double(max(acceptedDiff + rejectedDiff, 1)),
            systemLoad: SystemMonitor.shared.loadAverage.one
        )
        
        // Notifier le délégué
        await MainActor.run {
            self.delegate?.minerMonitor(self, didUpdateReport: report)
        }
        
        // Afficher un résumé
        self.printReport(report)
    }
    
    /// Affiche un rapport de surveillance dans la console
    private func printReport(_ report: Report) {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        
        let uptime = formatter.string(from: report.uptime) ?? "0s"
        let hashrateStr = String(format: "%.2f MH/s", report.hashrate / 1_000_000)
        let rejectRate = String(format: "%.1f%%", report.shareRejectRate * 100)
        
        print("""
        \n📊 RAPPORT DE SURVEILLANCE
        -------------------------
        ⏱️  Uptime: \(uptime)
        ⚡ Hashrate: \(hashrateStr)
        📦 Hashs totaux: \(report.totalHashes.formatted())
        ✅ Parts acceptées: \(report.sharesAccepted) (+\(report.newSharesAccepted))
        ❌ Parts rejetées: \(report.sharesRejected) (+\(report.newSharesRejected))
        📉 Taux de rejet: \(rejectRate)
        💻 Charge système: \(String(format: "%.1f%%", report.systemLoad * 100))
        -------------------------
        """)
    }
}

// MARK: - Types associés

public extension MinerMonitor {
    /// Rapport de surveillance du mineur
    struct Report {
        /// Horodatage du rapport
        public let timestamp: Date
        
        /// Temps de fonctionnement en secondes
        public let uptime: TimeInterval
        
        /// Hashrate actuel en haches par seconde
        public let hashrate: Double
        
        /// Nombre total de hachages effectués
        public let totalHashes: Int
        
        /// Nombre total de parts acceptées
        public let sharesAccepted: Int
        
        /// Nombre total de parts rejetées
        public let sharesRejected: Int
        
        /// Nouvelles parts acceptées depuis le dernier rapport
        public let newSharesAccepted: Int
        
        /// Nouvelles parts rejetées depuis le dernier rapport
        public let newSharesRejected: Int
        
        /// Taux de rejet des parts (0.0 - 1.0)
        public let shareRejectRate: Double
        
        /// Charge système actuelle (0.0 - 1.0)
        public let systemLoad: Double
    }
}

/// Protocole pour recevoir les mises à jour de surveillance
public protocol MinerMonitorDelegate: AnyObject {
    /// Appelé lorsqu'un nouveau rapport de surveillance est disponible
    /// - Parameters:
    ///   - monitor: Le moniteur qui a généré le rapport
    ///   - report: Le rapport de surveillance
    func minerMonitor(_ monitor: MinerMonitor, didUpdateReport report: MinerMonitor.Report)
}

// MARK: - Extension pour la surveillance système

// Utilisation de SystemMonitor.shared pour la surveillance des ressources système
