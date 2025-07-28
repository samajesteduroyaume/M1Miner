import Metal
import Foundation

/// Gère le traitement par lots pour optimiser les performances du minage
class BatchProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let batchPipeline: MTLComputePipelineState
    
    /// Taille maximale du lot pour le traitement par lots
    let maxBatchSize: Int
    
    /// Taille optimale du groupe de threads
    private let threadgroupSize: MTLSize
    
    /// Taille optimale de la grille de groupes de threads
    private let threadgroupCount: MTLSize
    
    /// Initialise le processeur par lots
    /// - Parameter device: Périphérique Metal à utiliser
    init?(device: MTLDevice) {
        self.device = device
        
        // Créer la file de commandes
        guard let queue = device.makeCommandQueue() else {
            print("Impossible de créer la file de commandes")
            return nil
        }
        self.commandQueue = queue
        
        // Charger la bibliothèque Metal
        guard let defaultLibrary = device.makeDefaultLibrary() else {
            print("Impossible de charger la bibliothèque Metal par défaut")
            return nil
        }
        
        // Créer les pipelines de calcul
        do {
            // Pipeline pour le traitement standard
            guard let kernelFunction = defaultLibrary.makeFunction(name: "kawpow_hash_optimized") else {
                print("Fonction de hachage non trouvée")
                return nil
            }
            self.computePipeline = try device.makeComputePipelineState(function: kernelFunction)
            
            // Pipeline pour le traitement par lots
            guard let batchFunction = defaultLibrary.makeFunction(name: "kawpow_hash_batch") else {
                print("Fonction de traitement par lots non trouvée")
                return nil
            }
            self.batchPipeline = try device.makeComputePipelineState(function: batchFunction)
            
            // Configurer les tailles de groupe de threads
            let maxTotalThreadsPerThreadgroup = computePipeline.maxTotalThreadsPerThreadgroup
            threadgroupSize = MTLSize(
                width: min(256, maxTotalThreadsPerThreadgroup),
                height: 1,
                depth: 1
            )
            
            // Déterminer la taille maximale du lot
            let threadsPerGrid = 1024 // Valeur par défaut
            threadgroupCount = MTLSize(
                width: (threadsPerGrid + threadgroupSize.width - 1) / threadgroupSize.width,
                height: 1,
                depth: 1
            )
            
            // Calculer la taille maximale du lot en fonction de la mémoire disponible
            let maxMem = device.recommendedMaxWorkingSetSize
            let memPerHash = 1024 // Estimation de la mémoire nécessaire par hachage (en octets)
            maxBatchSize = min(4096, Int(maxMem) / memPerHash) // Limite supérieure raisonnable
            
            print("BatchProcessor initialisé avec une taille de lot maximale de \(maxBatchSize) hachages")
            
        } catch {
            print("Erreur lors de l'initialisation des pipelines: \(error)")
            return nil
        }
    }
    
    /// Traite un lot de hachages de manière optimisée
    /// - Parameters:
    ///   - headers: Tableau d'en-têtes de blocs à hacher
    ///   - startNonce: Valeur de départ du nonce
    ///   - count: Nombre de hachages à calculer
    ///   - completion: Appelé avec les résultats du traitement
    func processBatch(headers: [Data], startNonce: UInt32, count: Int, completion: @escaping ([Data]?) -> Void) {
        // Vérifier les entrées
        guard !headers.isEmpty, count > 0 else {
            completion(nil)
            return
        }
        
        // Utiliser le traitement par lots si nous avons plusieurs en-têtes
        if headers.count > 1 {
            processBatchWithMultipleHeaders(headers: headers, startNonce: startNonce, count: count, completion: completion)
        } else {
            processBatchWithSingleHeader(header: headers[0], startNonce: startNonce, count: count, completion: completion)
        }
    }
    
    /// Traite un lot avec un seul en-tête et plusieurs nonces
    private func processBatchWithSingleHeader(header: Data, startNonce: UInt32, count: Int, completion: @escaping ([Data]?) -> Void) {
        // Vérifier que nous avons suffisamment de données d'en-tête
        guard header.count >= 32 else {
            print("En-tête trop court: \(header.count) octets")
            completion(nil)
            return
        }
        
        // Convertir l'en-tête en tableau d'entiers
        let headerInts = header.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [UInt32] in
            let buffer = ptr.bindMemory(to: UInt32.self)
            return Array(buffer)
        }
        
        // Créer les tampons de données
        guard let headerBuffer = device.makeBuffer(
            bytes: headerInts,
            length: headerInts.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Impossible de créer le tampon d'en-tête")
            completion(nil)
            return
        }
        
        // Créer un tampon pour les nonces
        let nonces = [startNonce] // Un seul nonce pour ce traitement
        guard let nonceBuffer = device.makeBuffer(
            bytes: nonces,
            length: nonces.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Impossible de créer le tampon de nonces")
            completion(nil)
            return
        }
        
        // Créer un tampon pour les résultats
        let resultCount = 4 // 4 entiers par hachage (128 bits)
        guard let resultBuffer = device.makeBuffer(
            length: count * resultCount * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Impossible de créer le tampon de résultats")
            completion(nil)
            return
        }
        
        // Créer une commande de calcul
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Impossible de créer la commande de calcul")
            completion(nil)
            return
        }
        
        // Configurer l'encodeur de commandes
        commandEncoder.setComputePipelineState(computePipeline)
        commandEncoder.setBuffer(headerBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(nonceBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(resultBuffer, offset: 0, index: 2)
        
        // Exécuter le noyau de calcul
        commandEncoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: threadgroupSize
        )
        
        // Finaliser l'encodage des commandes
        commandEncoder.endEncoding()
        
        // Exécuter la commande et traiter les résultats
        commandBuffer.addCompletedHandler { _ in
            // Extraire les résultats du tampon
            let resultPointer = resultBuffer.contents().bindMemory(to: UInt32.self, capacity: count * resultCount)
            var results = [Data]()
            
            for i in 0..<count {
                let hashData = Data(
                    bytes: resultPointer.advanced(by: i * resultCount),
                    count: resultCount * MemoryLayout<UInt32>.stride
                )
                results.append(hashData)
            }
            
            DispatchQueue.main.async {
                completion(results)
            }
        }
        
        // Soumettre la commande
        commandBuffer.commit()
    }
    
    /// Traite un lot avec plusieurs en-têtes et nonces
    private func processBatchWithMultipleHeaders(headers: [Data], startNonce: UInt32, count: Int, completion: @escaping ([Data]?) -> Void) {
        // Vérifier que nous avons suffisamment de données d'en-tête
        guard !headers.isEmpty, headers.allSatisfy({ $0.count >= 32 }) else {
            print("Un ou plusieurs en-têtes sont invalides")
            completion(nil)
            return
        }
        
        // Convertir les en-têtes en tableau d'entiers
        var headerInts = [UInt32]()
        for header in headers {
            let ints = header.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [UInt32] in
                let buffer = ptr.bindMemory(to: UInt32.self)
                return Array(buffer)
            }
            headerInts.append(contentsOf: ints)
        }
        
        // Générer les nonces
        var nonces = [UInt32]()
        for i in 0..<headers.count {
            nonces.append(startNonce + UInt32(i))
        }
        
        // Créer les tampons de données
        guard let headerBuffer = device.makeBuffer(
            bytes: headerInts,
            length: headerInts.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ), let nonceBuffer = device.makeBuffer(
            bytes: nonces,
            length: nonces.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Impossible de créer les tampons d'entrée")
            completion(nil)
            return
        }
        
        // Créer un tampon pour les résultats
        let resultCount = 4 // 4 entiers par hachage (128 bits)
        let totalResults = headers.count * resultCount
        guard let resultBuffer = device.makeBuffer(
            length: totalResults * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Impossible de créer le tampon de résultats")
            completion(nil)
            return
        }
        
        // Créer une commande de calcul
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Impossible de créer la commande de calcul")
            completion(nil)
            return
        }
        
        // Configurer l'encodeur de commandes pour le traitement par lots
        commandEncoder.setComputePipelineState(batchPipeline)
        commandEncoder.setBuffer(headerBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(nonceBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(resultBuffer, offset: 0, index: 2)
        
        // Définir la taille du lot
        var batchSize = UInt32(headers.count)
        commandEncoder.setBytes(&batchSize, length: MemoryLayout<UInt32>.stride, index: 3)
        
        // Exécuter le noyau de traitement par lots
        let gridSize = MTLSize(width: (headers.count + 3) / 4, height: 1, depth: 1)
        commandEncoder.dispatchThreads(
            gridSize,
            threadsPerThreadgroup: threadgroupSize
        )
        
        // Finaliser l'encodage des commandes
        commandEncoder.endEncoding()
        
        // Exécuter la commande et traiter les résultats
        commandBuffer.addCompletedHandler { _ in
            // Extraire les résultats du tampon
            let resultPointer = resultBuffer.contents().bindMemory(to: UInt32.self, capacity: totalResults)
            var results = [Data]()
            
            for i in 0..<headers.count {
                let hashData = Data(
                    bytes: resultPointer.advanced(by: i * resultCount),
                    count: resultCount * MemoryLayout<UInt32>.stride
                )
                results.append(hashData)
            }
            
            DispatchQueue.main.async {
                completion(results)
            }
        }
        
        // Soumettre la commande
        commandBuffer.commit()
    }
    
    /// Libère les ressources utilisées par le processeur
    deinit {
        // Les ressources Metal sont automatiquement libérées par ARC
        print("BatchProcessor libéré")
    }
}
