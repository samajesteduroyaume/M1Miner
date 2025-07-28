import Foundation
import Metal

class Benchmark {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let iterations: Int
    private let workSize: MTLSize
    
    init?(device: MTLDevice, functionName: String, iterations: Int = 100, workSize: MTLSize) {
        self.device = device
        self.iterations = iterations
        self.workSize = workSize
        
        // Création de la file de commandes
        guard let queue = device.makeCommandQueue() else {
            print("Impossible de créer la file de commandes")
            return nil
        }
        self.commandQueue = queue
        
        // Chargement de la fonction de calcul
        guard let defaultLibrary = device.makeDefaultLibrary(),
              let kernelFunction = defaultLibrary.makeFunction(name: functionName) else {
            print("Impossible de charger la fonction de hachage")
            return nil
        }
        
        // Création du pipeline de calcul
        do {
            self.pipelineState = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            print("Erreur lors de la création du pipeline: \(error)")
            return nil
        }
    }
    
    func run() -> (averageTime: Double, hashrate: Double) {
        var totalTime: Double = 0
        var results: [Double] = []
        
        // Exécution du benchmark plusieurs fois pour obtenir une moyenne stable
        for _ in 0..<iterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Création du buffer de commandes
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
                continue
            }
            
            // Configuration de l'encodeur de commandes
            commandEncoder.setComputePipelineState(pipelineState)
            
            // Configuration des threads
            let threadsPerThreadgroup = MTLSize(
                width: min(pipelineState.maxTotalThreadsPerThreadgroup, workSize.width),
                height: 1,
                depth: 1
            )
            
            let threadgroupCount = MTLSize(
                width: (workSize.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                height: (workSize.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                depth: 1
            )
            
            // Exécution du noyau
            commandEncoder.dispatchThreadgroups(threadgroupCount, 
                                             threadsPerThreadgroup: threadsPerThreadgroup)
            
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            let endTime = CFAbsoluteTimeGetCurrent()
            let iterationTime = endTime - startTime
            
            // Calcul du taux de hachage (hypothétique, à adapter selon l'algorithme)
            let hashesPerSecond = Double(workSize.width * workSize.height) / iterationTime
            
            totalTime += iterationTime
            results.append(hashesPerSecond)
        }
        
        // Calcul des statistiques
        let averageTime = totalTime / Double(iterations)
        let averageHashrate = results.reduce(0, +) / Double(results.count)
        
        // Calcul de l'écart-type
        let variance = results.map { pow($0 - averageHashrate, 2) }.reduce(0, +) / Double(results.count)
        let stdDev = sqrt(variance)
        
        print("\n=== Résultats du benchmark ===")
        print("Itérations: \(iterations)")
        print("Temps moyen par itération: \(String(format: "%.6f", averageTime * 1000)) ms")
        print("Taux de hachage moyen: \(formatHashrate(averageHashrate))")
        print("Écart-type: ±\(formatHashrate(stdDev)) (CV: \(String(format: "%.2f", (stdDev / averageHashrate) * 100))%)")
        
        return (averageTime, averageHashrate)
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
    
    // Fonction utilitaire pour générer des données d'entrée aléatoires
    static func generateRandomData(length: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: length)
        _ = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, length, buffer.baseAddress!)
        }
        return data
    }
}

// Fonction principale pour exécuter le benchmark depuis la ligne de commande
func runBenchmark() {
    print("Démarrage du benchmark du mineur M1...")
    
    // Vérification de la disponibilité de Metal
    guard let device = MTLCreateSystemDefaultDevice() else {
        print("Aucun périphérique Metal compatible trouvé")
        return
    }
    
    print("Périphérique: \(device.name)")
    print("Mémoire unifiée: \(device.hasUnifiedMemory ? "Oui" : "Non")")
    print("Taille maximale des groupes de threads: \(device.maxThreadsPerThreadgroup)")
    
    // Configuration du benchmark
    let workSize = MTLSize(width: 1_000_000, height: 1, depth: 1) // 1 million de threads
    let iterations = 10
    
    // Exécution du benchmark pour KawPow
    print("\n=== Benchmark KawPow ===")
    if let kawpowBenchmark = Benchmark(
        device: device,
        functionName: "kawpow_hash",
        iterations: iterations,
        workSize: workSize
    ) {
        let result = kawpowBenchmark.run()
        print("Résultat final: \(formatHashrate(result.hashrate))")
    } else {
        print("Impossible d'initialiser le benchmark KawPow")
    }
    
    // Exécution du benchmark pour GhostRider (si disponible)
    print("\n=== Benchmark GhostRider ===")
    if let ghostriderBenchmark = Benchmark(
        device: device,
        functionName: "ghostrider_hash",
        iterations: iterations,
        workSize: workSize
    ) {
        let result = ghostriderBenchmark.run()
        print("Résultat final: \(formatHashrate(result.hashrate))")
    } else {
        print("Le benchmark GhostRider n'est pas disponible")
    }
}

// Fonction utilitaire pour formater le taux de hachage
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

// Pour exécuter le benchmark, créez une cible d'application séparée
// qui appelle la fonction runBenchmark()
