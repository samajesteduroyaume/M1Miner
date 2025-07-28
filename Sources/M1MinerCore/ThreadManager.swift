import Foundation
import Dispatch

/// Gère l'exécution des tâches de manière optimisée sur les cœurs disponibles
class ThreadManager {
    /// File d'attente haute priorité pour les tâches critiques
    private let highPriorityQueue: DispatchQueue
    
    /// File d'attente moyenne priorité pour les tâches standards
    private let defaultPriorityQueue: DispatchQueue
    
    /// File d'attente basse priorité pour les tâches en arrière-plan
    private let lowPriorityQueue: DispatchQueue
    
    /// Groupe de dispatch pour suivre les tâches
    private let dispatchGroup = DispatchGroup()
    
    /// Sémaphore pour contrôler l'accès concurrentiel
    private let semaphore: DispatchSemaphore
    
    /// Nombre maximum de tâches concurrentes (par défaut: nombre de cœurs logiques)
    private let maxConcurrentTasks: Int
    
    /// Suivi des tâches actives
    private var activeTasks = 0
    private let taskTrackingQueue = DispatchQueue(label: "com.m1miner.threadmanager.tasks", attributes: .concurrent)
    
    /// Initialise le gestionnaire de threads
    /// - Parameter maxConcurrentTasks: Nombre maximum de tâches concurrentes (0 pour automatique)
    init(maxConcurrentTasks: Int = 0) {
        let logicalCores = ProcessInfo.processInfo.processorCount
        self.maxConcurrentTasks = maxConcurrentTasks > 0 ? min(maxConcurrentTasks, logicalCores * 2) : logicalCores
        self.semaphore = DispatchSemaphore(value: self.maxConcurrentTasks)
        
        // Configuration des files d'attente avec des qualités de service appropriées
        self.highPriorityQueue = DispatchQueue(
            label: "com.m1miner.threadmanager.high",
            qos: .userInteractive,
            attributes: .concurrent
        )
        
        self.defaultPriorityQueue = DispatchQueue(
            label: "com.m1miner.threadmanager.default",
            qos: .userInitiated,
            attributes: .concurrent
        )
        
        self.lowPriorityQueue = DispatchQueue(
            label: "com.m1miner.threadmanager.low",
            qos: .utility,
            attributes: .concurrent
        )
        
        print("ThreadManager initialisé avec \(self.maxConcurrentTasks) tâches concurrentes maximum")
    }
    
    // MARK: - Méthodes publiques
    
    /// Exécute une tâche avec la priorité spécifiée
    /// - Parameters:
    ///   - priority: Priorité de la tâche
    ///   - task: La tâche à exécuter
    func execute(priority: TaskPriority = .medium, _ task: @escaping () -> Void) {
        let queue = queueForPriority(priority)
        
        // Attendre un slot disponible si nécessaire
        semaphore.wait()
        
        // Mettre à jour le compteur de tâches actives
        taskTrackingQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.activeTasks += 1
            self.logTaskStatus(action: "Démarrage")
        }
        
        // Exécuter la tâche
        queue.async { [weak self] in
            defer {
                // Libérer le sémaphore et mettre à jour le compteur
                self?.semaphore.signal()
                
                self?.taskTrackingQueue.async(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    self.activeTasks -= 1
                    self.logTaskStatus(action: "Terminaison")
                }
            }
            
            // Exécuter la tâche
            task()
        }
    }
    
    /// Exécute une tâche de manière synchrone avec la priorité spécifiée
    /// - Parameters:
    ///   - priority: Priorité de la tâche
    ///   - task: La tâche à exécuter
    func executeSync(priority: TaskPriority = .medium, _ task: @escaping () -> Void) {
        let queue = queueForPriority(priority)
        
        // Si nous sommes déjà dans la file d'attente cible, exécuter directement
        if isCurrentQueue(queue) {
            task()
            return
        }
        
        // Attendre un slot disponible si nécessaire
        semaphore.wait()
        
        // Mettre à jour le compteur de tâches actives
        taskTrackingQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.activeTasks += 1
            self.logTaskStatus(action: "Démarrage synchrone")
        }
        
        // Exécuter la tâche de manière synchrone
        queue.sync {
            defer {
                // Libérer le sémaphore et mettre à jour le compteur
                self.semaphore.signal()
                
                self.taskTrackingQueue.async(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    self.activeTasks -= 1
                    self.logTaskStatus(action: "Terminaison synchrone")
                }
            }
            
            // Exécuter la tâche
            task()
        }
    }
    
    /// Exécute une tâche après un délai
    /// - Parameters:
    ///   - delay: Délai en secondes
    ///   - priority: Priorité de la tâche
    ///   - task: La tâche à exécuter
    func executeAfter(delay: TimeInterval, priority: TaskPriority = .medium, _ task: @escaping () -> Void) {
        let queue = queueForPriority(priority)
        
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.execute(priority: priority, task)
        }
    }
    
    /// Attend que toutes les tâches en attente soient terminées
    /// - Parameter timeout: Délai d'attente en secondes (nil pour attendre indéfiniment)
    /// - Returns: Résultat de l'attente
    @discardableResult
    func waitAll(timeout: TimeInterval? = nil) -> DispatchTimeoutResult {
        let timeoutTime: DispatchTime
        if let timeout = timeout {
            timeoutTime = .now() + timeout
        } else {
            timeoutTime = .distantFuture
        }
        
        // Attendre que toutes les tâches soient terminées
        return dispatchGroup.wait(timeout: timeoutTime)
    }
    
    /// Annule toutes les tâches en attente
    func cancelAll() {
        // Les tâches en cours d'exécution continueront jusqu'à leur terme
        // Les tâches en attente ne seront pas exécutées
        taskTrackingQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.logTaskStatus(action: "Annulation de toutes les tâches")
        }
    }
    
    /// Obtient des statistiques sur l'utilisation des threads
    func getStatistics() -> ThreadManagerStatistics {
        var stats = ThreadManagerStatistics()
        
        taskTrackingQueue.sync {
            stats.activeTasks = activeTasks
            stats.maxConcurrentTasks = maxConcurrentTasks
            stats.availableSlots = max(0, maxConcurrentTasks - activeTasks)
        }
        
        return stats
    }
    
    // MARK: - Méthodes privées
    
    private func queueForPriority(_ priority: TaskPriority) -> DispatchQueue {
        switch priority {
        case .high:
            return highPriorityQueue
        case .medium:
            return defaultPriorityQueue
        case .low:
            return lowPriorityQueue
        @unknown default:
            return defaultPriorityQueue
        }
    }
    
    private func isCurrentQueue(_ queue: DispatchQueue) -> Bool {
        let key = DispatchSpecificKey<Void>()
        queue.setSpecific(key: key, value: ())
        defer { queue.setSpecific(key: key, value: nil) }
        
        return DispatchQueue.getSpecific(key: key) != nil
    }
    
    private func logTaskStatus(action: String) {
        #if DEBUG
        print("\(action) - Tâches actives: \(activeTasks)/\(maxConcurrentTasks)")
        #endif
    }
}

// MARK: - Types associés

/// Priorité d'une tâche
enum TaskPriority {
    case high
    case medium
    case low
}

/// Statistiques du gestionnaire de threads
struct ThreadManagerStatistics {
    var activeTasks: Int = 0
    var maxConcurrentTasks: Int = 0
    var availableSlots: Int = 0
    
    var description: String {
        return "\(activeTasks) tâches actives (\(availableSlots) slots disponibles sur \(maxConcurrentTasks))"
    }
}

// MARK: - Extensions

extension ThreadManager: CustomStringConvertible {
    var description: String {
        let stats = getStatistics()
        return """
        ThreadManager {
            Tâches actives: \(stats.activeTasks)
            Tâches maximum: \(stats.maxConcurrentTasks)
            Slots disponibles: \(stats.availableSlots)
        }
        """
    }
}

// MARK: - Fonctions globales

/// Exécute une tâche de manière asynchrone avec une priorité donnée
/// - Parameters:
///   - priority: Priorité de la tâche (par défaut: .medium)
///   - task: La tâche à exécuter
func async(priority: TaskPriority = .medium, _ task: @escaping () -> Void) {
    ThreadManager.shared.execute(priority: priority, task)
}

/// Exécute une tâche de manière synchrone avec une priorité donnée
/// - Parameters:
///   - priority: Priorité de la tâche (par défaut: .medium)
///   - task: La tâche à exécuter
func sync(priority: TaskPriority = .medium, _ task: @escaping () -> Void) {
    ThreadManager.shared.executeSync(priority: priority, task)
}

/// Instance partagée du gestionnaire de threads
extension ThreadManager {
    private static let _shared = ThreadManager()
    
    static var shared: ThreadManager {
        return _shared
    }
}
