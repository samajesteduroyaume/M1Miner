import Foundation

// Extension pour une meilleure gestion des verrous avec syntaxe de fermeture
public extension NSLock {
    /// Exécute une fermeture de manière thread-safe
    /// - Parameter body: La fermeture à exécuter de manière thread-safe
    /// - Returns: La valeur de retour de la fermeture
    /// - Throws: Toute erreur levée par la fermeture
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
    
    /// Exécute une fermeture de manière thread-safe (version asynchrone)
    /// - Parameter body: La fermeture asynchrone à exécuter de manière thread-safe
    /// - Returns: La valeur de retour de la fermeture
    /// - Throws: Toute erreur levée par la fermeture
    func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        lock()
        defer { unlock() }
        return try await body()
    }
}
