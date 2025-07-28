import Metal
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Gère l'allocation et la libération efficaces de la mémoire pour les opérations de minage
class MemoryManager {
    private let device: MTLDevice
    private var bufferPool: [Int: [MTLBuffer]] = [:]
    private let lock = NSLock()
    private var peakMemoryUsage: UInt64 = 0
    private var currentMemoryUsage: UInt64 = 0
    
    /// Suivi des allocations pour le débogage
    private var activeBuffers: [ObjectIdentifier: (buffer: MTLBuffer, label: String)] = [:]
    
    /// Seuil d'alerte pour l'utilisation de la mémoire (en octets)
    var memoryWarningThreshold: UInt64 = 1_073_741_824 // 1 Go par défaut
    
    /// Callback appelé lorsque l'utilisation de la mémoire atteint le seuil d'alerte
    var onMemoryWarning: ((UInt64) -> Void)?
    
    /// Initialise le gestionnaire de mémoire
    /// - Parameter device: Périphérique Metal à utiliser
    init(device: MTLDevice) {
        self.device = device
        
        // Surveiller les notifications de mémoire faible
        #if os(iOS)
        let memoryNotification = UIApplication.didReceiveMemoryWarningNotification
        #elseif os(macOS)
        // Sur macOS, nous utilisons une notification personnalisée car NSApplication n'a pas de notification de mémoire faible
        let memoryNotification = NSApplication.willResignActiveNotification
        #endif
        
        // S'abonner uniquement si nous avons une notification valide
        #if os(iOS) || os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: memoryNotification,
            object: nil
        )
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        print("MemoryManager libéré. Utilisation mémoire maximale: \(formatMemory(peakMemoryUsage))")
    }
    
    /// Alloue un nouveau tampon avec la taille spécifiée
    /// - Parameters:
    ///   - length: Taille du tampon en octets
    ///   - options: Options d'allocation (par défaut: .storageModeShared)
    ///   - label: Étiquette pour le débogage
    /// - Returns: Un tampon Metal alloué ou nil en cas d'échec
    func makeBuffer(
        length: Int,
        options: MTLResourceOptions = [.storageModeShared],
        label: String? = nil
    ) -> MTLBuffer? {
        // Vérifier la taille de la demande
        guard length > 0 else {
            print("Tentative d'allocation d'un tampon de taille nulle")
            return nil
        }
        
        // Vérifier si nous avons un tampon réutilisable disponible
        if let buffer = dequeueReusableBuffer(length: length, options: options) {
            if let label = label {
                setLabel(label, for: buffer)
            }
            return buffer
        }
        
        // Allouer un nouveau tampon
        guard let buffer = device.makeBuffer(length: length, options: options) else {
            print("Échec de l'allocation d'un tampon de \(formatMemory(UInt64(length)))")
            return nil
        }
        
        // Mettre à jour le suivi de la mémoire
        updateMemoryUsage(by: UInt64(length))
        
        // Étiqueter le tampon pour le débogage
        if let label = label {
            setLabel(label, for: buffer)
        } else {
            setLabel("Unlabeled_\\(UUID().uuidString.prefix(8))", for: buffer)
        }
        
        print("Alloué: \(buffer.label ?? "sans étiquette") - \(formatMemory(UInt64(length)))")
        
        return buffer
    }
    
    /// Libère un tampon et le rend disponible pour une réutilisation ultérieure
    /// - Parameter buffer: Le tampon à libérer
    func releaseBuffer(_ buffer: MTLBuffer) {
        let length = buffer.length
        let options = buffer.resourceOptions
        
        // Supprimer l'étiquette du tampon
        let id = ObjectIdentifier(buffer)
        let label = activeBuffers.removeValue(forKey: id)?.label
        
        // Réinitialiser le contenu du tampon (pour la sécurité)
        let contents = buffer.contents()
        memset(contents, 0, length)
        
        // Ajouter le tampon à la piscine de réutilisation
        enqueueBuffer(buffer, length: length, options: options)
        
        print("Libéré: \(label ?? "tampon inconnu") - \(formatMemory(UInt64(length)))")
    }
    
    /// Libère toute la mémoire non utilisée
    func dumpActiveBuffers() {
        lock.lock()
        defer { lock.unlock() }
        
        print("\n=== Tampons actifs (\(activeBuffers.count)) ===")
        for (_, value) in activeBuffers {
            print("-\(value.label): \(formatMemory(UInt64(value.buffer.length)))")
        }
    }
    
    /// Obtient les statistiques d'utilisation de la mémoire
    /// - Returns: Un tuple contenant (mémoire utilisée, mémoire de pointe, nombre de tampons actifs)
    func memoryStatistics() -> (used: UInt64, peak: UInt64, activeBuffers: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (currentMemoryUsage, peakMemoryUsage, activeBuffers.count)
    }
    
    // MARK: - Méthodes privées
    
    private func enqueueBuffer(_ buffer: MTLBuffer, length: Int, options: MTLResourceOptions) {
        lock.lock()
        defer { lock.unlock() }
        
        // Vérifier si nous devons libérer de la mémoire
        if currentMemoryUsage > memoryWarningThreshold {
            // Libérer les tampons les plus anciens
            if let (_, buffers) = bufferPool.first {
                if !buffers.isEmpty {
                    let oldBuffer = buffers[0]
                    let oldLength = oldBuffer.length
                    bufferPool[oldLength]?.removeFirst()
                    currentMemoryUsage -= UInt64(oldLength)
                    print("Mémoire critique: libération d'un tampon de \(formatMemory(UInt64(oldLength)))")
                }
            }
        }
        
        // Ajouter le tampon à la piscine
        if bufferPool[length] == nil {
            bufferPool[length] = []
        }
        
        // Limiter le nombre de tampons en cache par taille
        if let count = bufferPool[length]?.count, count < 5 {
            bufferPool[length]?.append(buffer)
        } else {
            // Libérer le tampon s'il y en a trop dans le cache
            currentMemoryUsage -= UInt64(length)
        }
    }
    
    private func dequeueReusableBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        lock.lock()
        defer { lock.unlock() }
        
        // Essayer de trouver un tampon de la même taille
        if var buffers = bufferPool[length], !buffers.isEmpty {
            // Rechercher un tampon avec les mêmes options
            if let index = buffers.firstIndex(where: { $0.resourceOptions == options }) {
                let buffer = buffers.remove(at: index)
                bufferPool[length] = buffers.isEmpty ? nil : buffers
                
                // Mettre à jour le suivi des tampons actifs
                let id = ObjectIdentifier(buffer)
                activeBuffers[id] = (buffer, "Reused_\(UUID().uuidString.prefix(8))")
                
                return buffer
            }
        }
        
        return nil
    }
    
    private func updateMemoryUsage(by delta: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        
        currentMemoryUsage += delta
        peakMemoryUsage = max(peakMemoryUsage, currentMemoryUsage)
        
        // Vérifier le seuil d'alerte
        if currentMemoryUsage > memoryWarningThreshold {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onMemoryWarning?(self.currentMemoryUsage)
            }
        }
    }
    
    private func setLabel(_ label: String, for buffer: MTLBuffer) {
        buffer.label = label
        let id = ObjectIdentifier(buffer)
        activeBuffers[id] = (buffer, label)
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Alerte mémoire système reçue")
        // Libérer la mémoire inutilisée
        freeAllUnusedBuffers()
    }
    
    /// Libère tous les buffers inutilisés du pool
    private func freeAllUnusedBuffers() {
        lock.lock()
        defer { lock.unlock() }
        
        var totalFreed: UInt64 = 0
        var buffersFreed = 0
        
        for (size, buffers) in bufferPool {
            // Ne garder que les buffers actifs (en utilisant les identifiants d'objet pour la comparaison)
            let activeBufferIds = Set(activeBuffers.values.map { ObjectIdentifier($0.buffer) })
            var activeBuffersList: [MTLBuffer] = []
            var unusedBuffersList: [MTLBuffer] = []
            
            // Séparer les buffers actifs des inutilisés
            for buffer in buffers {
                if activeBufferIds.contains(ObjectIdentifier(buffer)) {
                    activeBuffersList.append(buffer)
                } else {
                    unusedBuffersList.append(buffer)
                }
            }
            
            // Libérer la mémoire des buffers inutilisés
            for buffer in unusedBuffersList {
                totalFreed += UInt64(buffer.allocatedSize)
                buffersFreed += 1
            }
            
            // Mettre à jour le pool avec uniquement les buffers actifs
            bufferPool[size] = activeBuffersList
        }
        
        if buffersFreed > 0 {
            currentMemoryUsage = currentMemoryUsage > totalFreed ? currentMemoryUsage - totalFreed : 0
            print("♻️ Libéré \(formatMemory(totalFreed)) dans \(buffersFreed) buffers inutilisés")
        }
    }
    
    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// Extension pour le débogage
extension MemoryManager: CustomStringConvertible {
    var description: String {
        let stats = memoryStatistics()
        return """
        MemoryManager {
            Utilisation actuelle: \(formatMemory(stats.used))
            Utilisation max: \(formatMemory(stats.peak))
            Tampons actifs: \(stats.activeBuffers)
            Tampons en cache: \(bufferPool.values.map { $0.count }.reduce(0, +))
        }
        """
    }
}

// Extension pour les notifications système
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let memoryManagerDidReceiveWarning = Notification.Name("MemoryManagerDidReceiveWarning")
}
