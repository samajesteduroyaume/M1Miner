import Foundation
#if os(macOS)
import Darwin

// Constante utilisée pour le calcul de la charge moyenne
private let LOAD_SCALE: Int32 = 1000
#elseif os(Linux)
import Glibc
#endif

/// Classe pour surveiller les ressources système
public final class SystemMonitor {
    // Singleton
    public static let shared = SystemMonitor()
    
    // Dernières lectures
    private var lastCPUInfo: host_cpu_load_info?
    private var lastCPUTime: timeval = timeval()
    
    // Verrou pour l'accès thread-safe
    private let lock = NSLock()
    
    private init() {
        // Initialiser avec les valeurs actuelles
        _ = self.cpuUsage
    }
    
    // MARK: - Propriétés publiques
    
    /// Charge moyenne du système (1m, 5m, 15m)
    public var loadAverage: (one: Double, five: Double, fifteen: Double) {
        var loadavg: [Double] = [0, 0, 0]
        
        #if os(macOS)
        // Sur macOS, utiliser host_statistics pour obtenir les moyennes
        var mib = [CTL_VM, VM_LOADAVG]
        var size = MemoryLayout<Int32>.size * 3
        
        var data = [Int32](repeating: 0, count: 3)
        let result = sysctl(&mib, u_int(mib.count), &data, &size, nil, 0)
        
        if result == 0 {
            loadavg = data.map { Double($0) / Double(LOAD_SCALE) }
        }
        #elseif os(Linux)
        // Sur Linux, lire /proc/loadavg
        if let content = try? String(contentsOfFile: "/proc/loadavg") {
            let components = content.components(separatedBy: .whitespaces).prefix(3)
            loadavg = components.compactMap { Double($0) }
        }
        #endif
        
        return (loadavg[safe: 0] ?? 0, 
                loadavg[safe: 1] ?? 0, 
                loadavg[safe: 2] ?? 0)
    }
    
    /// Utilisation du CPU (0.0 à 1.0)
    public var cpuUsage: Double {
        lock.lock()
        defer { lock.unlock() }
        
        #if os(macOS)
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let hostInfo = host_cpu_load_info_t.allocate(capacity: 1)
        
        let result = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
        }
        
        guard result == KERN_SUCCESS else {
            return 0.0
        }
        
        let data = hostInfo.move()
        hostInfo.deallocate()
        
        let userTicks = Double(data.cpu_ticks.0)
        let systemTicks = Double(data.cpu_ticks.1)
        let idleTicks = Double(data.cpu_ticks.3)
        
        // Calculer le total des ticks (variable non utilisée pour le moment)
        let _ = userTicks + systemTicks + idleTicks
        
        // Calculer la différence avec la dernière lecture
        var usage: Double = 0.0
        
        if let last = lastCPUInfo {
            let userDiff = userTicks - Double(last.cpu_ticks.0)
            let systemDiff = systemTicks - Double(last.cpu_ticks.1)
            let idleDiff = idleTicks - Double(last.cpu_ticks.3)
            let totalDiff = userDiff + systemDiff + idleDiff
            
            if totalDiff > 0 {
                usage = (userDiff + systemDiff) / totalDiff
            }
        }
        
        // Mettre à jour la dernière lecture
        lastCPUInfo = data
        
        return max(0.0, min(1.0, usage))
        #else
        // Implémentation simplifiée pour Linux
        return 0.0
        #endif
    }
    
    /// Mémoire utilisée en octets
    public var memoryUsage: UInt64 {
        #if os(macOS)
        var stats = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return stats.phys_footprint
        #elseif os(Linux)
        // Implémentation pour Linux
        return 0
        #endif
    }
    
    /// Mémoire totale en octets
    public var totalMemory: UInt64 {
        #if os(macOS)
        return ProcessInfo.processInfo.physicalMemory
        #elseif os(Linux)
        // Implémentation pour Linux
        return 0
        #endif
    }
}

// MARK: - Extensions d'aide

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
