import Foundation
import Metal
import System

/// Classe de surveillance des performances du mineur
class PerformanceMonitor {
    private let updateInterval: TimeInterval
    private var timer: Timer?
    private var startTime: Date
    private var lastUpdateTime: Date
    private var lastHashCount: UInt64 = 0
    private var samples: [Double] = []
    private let maxSamples = 60 // Nombre d'échantillons à conserver pour les moyennes mobiles
    
    var currentHashrate: Double = 0
    var averageHashrate: Double = 0
    var totalHashes: UInt64 = 0
    var sharesAccepted: UInt64 = 0
    var sharesRejected: UInt64 = 0
    var uptime: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
    
    var onUpdate: ((PerformanceMetrics) -> Void)?
    
    struct PerformanceMetrics {
        let currentHashrate: Double
        let averageHashrate: Double
        let totalHashes: UInt64
        let sharesAccepted: UInt64
        let sharesRejected: UInt64
        let uptime: TimeInterval
        let temperature: Double?
        let powerUsage: Double?
        let fanSpeed: Int?
    }
    
    init(updateInterval: TimeInterval = 5.0) {
        self.updateInterval = updateInterval
        self.startTime = Date()
        self.lastUpdateTime = startTime
    }
    
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
        
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        } else {
            print("Impossible de démarrer le minuteur de surveillance des performances")
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    func incrementHashCount(by count: UInt64 = 1) {
        totalHashes += count
    }
    
    func incrementShares(accepted: Bool = true) {
        if accepted {
            sharesAccepted += 1
        } else {
            sharesRejected += 1
        }
    }
    
    private func updateMetrics() {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        // Calcul du taux de hachage actuel (h/s)
        currentHashrate = Double(totalHashes - lastHashCount) / timeSinceLastUpdate
        
        // Mise à jour des échantillons pour la moyenne mobile
        samples.append(currentHashrate)
        if samples.count > maxSamples {
            samples.removeFirst()
        }
        
        // Calcul de la moyenne mobile
        averageHashrate = samples.reduce(0, +) / Double(samples.count)
        
        // Mise à jour des compteurs
        lastHashCount = totalHashes
        lastUpdateTime = now
        
        // Récupération des métriques système
        let systemMetrics = getSystemMetrics()
        
        // Notification des observateurs
        let metrics = PerformanceMetrics(
            currentHashrate: currentHashrate,
            averageHashrate: averageHashrate,
            totalHashes: totalHashes,
            sharesAccepted: sharesAccepted,
            sharesRejected: sharesRejected,
            uptime: uptime,
            temperature: systemMetrics.temperature,
            powerUsage: systemMetrics.powerUsage,
            fanSpeed: systemMetrics.fanSpeed
        )
        
        DispatchQueue.main.async {
            self.onUpdate?(metrics)
        }
    }
    
    private func getSystemMetrics() -> (temperature: Double?, powerUsage: Double?, fanSpeed: Int?) {
        var temperature: Double? = nil
        var powerUsage: Double? = nil
        var fanSpeed: Int? = nil
        
        // Lecture des capteurs système (implémentation spécifique à macOS)
        #if os(macOS)
        // Utilisation de la commande 'pmset' pour obtenir la consommation d'énergie
        let powerTask = Process()
        powerTask.launchPath = "/usr/bin/pmset"
        powerTask.arguments = ["-g", "ps"]
        
        let powerPipe = Pipe()
        powerTask.standardOutput = powerPipe
        
        do {
            try powerTask.run()
            let powerData = powerPipe.fileHandleForReading.readDataToEndOfFile()
            if let powerOutput = String(data: powerData, encoding: .utf8) {
                // Extraction de la consommation d'énergie en mW
                let pattern = "(\\d+) mW"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(powerOutput.startIndex..<powerOutput.endIndex, in: powerOutput)
                    if let match = regex.firstMatch(in: powerOutput, options: [], range: range) {
                        if let range = Range(match.range(at: 1), in: powerOutput) {
                            let mWString = String(powerOutput[range])
                            powerUsage = Double(mWString).map { $0 / 1000.0 } // Conversion en Watts
                        }
                    }
                }
            }
        } catch {
            print("Erreur lors de la lecture de la consommation d'énergie: \(error)")
        }
        
        // Utilisation de la commande 'osx-cpu-temp' (nécessite une installation préalable)
        let tempTask = Process()
        tempTask.launchPath = "/usr/local/bin/osx-cpu-temp"
        
        let tempPipe = Pipe()
        tempTask.standardOutput = tempPipe
        
        do {
            try tempTask.run()
            let tempData = tempPipe.fileHandleForReading.readDataToEndOfFile()
            if let tempOutput = String(data: tempData, encoding: .utf8) {
                // Extraction de la température en degrés Celsius
                let pattern = "([0-9.]+)°C"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(tempOutput.startIndex..<tempOutput.endIndex, in: tempOutput)
                    if let match = regex.firstMatch(in: tempOutput, options: [], range: range) {
                        if let range = Range(match.range(at: 1), in: tempOutput) {
                            let tempString = String(tempOutput[range])
                            temperature = Double(tempString)
                        }
                    }
                }
            }
        } catch {
            // La commande osx-cpu-temp n'est probablement pas installée
            // Vous pouvez l'installer avec: brew install osx-cpu-temp
        }
        
        // Lecture de la vitesse du ventilateur (nécessite des privilèges élevés)
        let fanTask = Process()
        fanTask.launchPath = "/usr/bin/sudo"
        fanTask.arguments = ["-n", "-S", "/usr/local/bin/smc", "-k", "F0Ac", "-r"]
        
        let fanPipe = Pipe()
        fanTask.standardOutput = fanPipe
        fanTask.standardError = Pipe()
        
        do {
            // Note: Cela nécessitera un mot de passe sudo
            try fanTask.run()
            let fanData = fanPipe.fileHandleForReading.readDataToEndOfFile()
            if let fanOutput = String(data: fanData, encoding: .utf8) {
                // Extraction de la vitesse du ventilateur en RPM
                let pattern = "[^0-9]*([0-9]+)"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(fanOutput.startIndex..<fanOutput.endIndex, in: fanOutput)
                    if let match = regex.firstMatch(in: fanOutput, options: [], range: range) {
                        if let range = Range(match.range(at: 1), in: fanOutput) {
                            let fanString = String(fanOutput[range])
                            fanSpeed = Int(fanString)
                        }
                    }
                }
            }
        } catch {
            // La commande smc n'est probablement pas installée ou nécessite des privilèges
        }
        #endif
        
        return (temperature, powerUsage, fanSpeed)
    }
    
    func formatHashrate(_ hashrate: Double) -> String {
        let units = ["H/s", "kH/s", "MH/s", "GH/s", "TH/s"]
        var speed = hashrate
        var unitIndex = 0
        
        while speed >= 1000 && unitIndex < units.count - 1 {
            speed /= 1000
            unitIndex += 1
        }
        
        return String(format: "%.2f \(units[unitIndex])", speed)
    }
    
    func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// Extension pour afficher les métriques dans la console
extension PerformanceMonitor.PerformanceMetrics: CustomStringConvertible {
    var description: String {
        var lines: [String] = []
        
        // Ligne 1: Taux de hachage
        lines.append("╔" + String(repeating: "═", count: 78) + "╗")
        
        // Ligne 2: Taux de hachage actuel et moyen
        let hashrateLine = "║ 🔄 Taux de hachage: \(formatHashrate(currentHashrate)) (moy: \(formatHashrate(averageHashrate)))"
            .padding(toLength: 78, withPad: " ", startingAt: 0) + "║"
        lines.append(hashrateLine)
        
        // Ligne 3: Temps de fonctionnement
        let uptimeLine = "║ ⏱  Temps de fonctionnement: \(formatTimeInterval(uptime))"
            .padding(toLength: 78, withPad: " ", startingAt: 0) + "║"
        lines.append(uptimeLine)
        
        // Ligne 4: Actions minières
        let sharesLine = "║ ✅ Actions: \(sharesAccepted) acceptées | ❌ \(sharesRejected) rejetées | 📊 Total: \(totalHashes.formatted()) hachages"
            .padding(toLength: 78, withPad: " ", startingAt: 0) + "║"
        lines.append(sharesLine)
        
        // Ligne 5: Métriques système
        var systemLine = "║ 💻 Système: "
        if let temp = temperature {
            systemLine += "🌡️ \(String(format: "%.1f", temp))°C | "
        }
        if let power = powerUsage {
            systemLine += "⚡ \(String(format: "%.1f", power))W | "
        }
        if let fan = fanSpeed {
            systemLine += "💨 \(fan) RPM"
        }
        systemLine = systemLine.padding(toLength: 78, withPad: " ", startingAt: 0) + "║"
        lines.append(systemLine)
        
        // Ligne 6: Barre de progression (simulée)
        let progress = Int((Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10.0)) * 7.0)
        let progressBar = "║ [" + String(repeating: "=", count: progress) + 
                        ">" + 
                        String(repeating: " ", count: 70 - progress) + "] ║"
        lines.append(progressBar)
        
        // Dernière ligne
        lines.append("╚" + String(repeating: "═", count: 78) + "╝")
        
        return lines.joined(separator: "\n")
    }
    
    private func formatHashrate(_ hashrate: Double) -> String {
        let units = ["H/s", "kH/s", "MH/s", "GH/s", "TH/s"]
        var speed = hashrate
        var unitIndex = 0
        
        while speed >= 1000 && unitIndex < units.count - 1 {
            speed /= 1000
            unitIndex += 1
        }
        
        return String(format: "%.2f \(units[unitIndex])", speed)
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
