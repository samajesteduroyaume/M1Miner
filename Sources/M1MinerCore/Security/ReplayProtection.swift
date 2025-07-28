import Foundation

/// Protège contre les attaques par rejeu en gardant une trace des nonces déjà utilisés
public final class ReplayProtection {
    private let windowSize: Int
    private var usedNonces: Set<String> = []
    private let queue = DispatchQueue(label: "com.stratumclient.replayprotection", attributes: .concurrent)
    
    /// Initialise le système de protection contre le rejeu
    /// - Parameter windowSize: Nombre maximum de nonces à conserver en mémoire (par défaut: 1000)
    public init(windowSize: Int = 1000) {
        self.windowSize = windowSize
    }
    
    /// Vérifie si un nonce a déjà été utilisé
    /// - Parameters:
    ///   - nonce: Le nonce à vérifier
    ///   - jobId: L'ID du job associé au nonce
    /// - Returns: Vrai si le nonce est valide (non utilisé), faux sinon
    public func isNonceValid(_ nonce: String, forJobId jobId: String) -> Bool {
        let key = "\(jobId):\(nonce)"
        
        return queue.sync {
            !usedNonces.contains(key)
        }
    }
    
    /// Enregistre un nonce comme utilisé
    /// - Parameters:
    ///   - nonce: Le nonce à enregistrer
    ///   - jobId: L'ID du job associé au nonce
    public func markNonceAsUsed(_ nonce: String, forJobId jobId: String) {
        let key = "\(jobId):\(nonce)"
        
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Si on atteint la taille maximale, on supprime les anciennes entrées
            if self.usedNonces.count >= self.windowSize {
                // On supprime les entrées les plus anciennes (les 10% les plus anciennes)
                let excessCount = self.usedNonces.count - Int(Double(self.windowSize) * 0.9)
                if excessCount > 0 {
                    let excessKeys = Array(self.usedNonces.prefix(excessCount))
                    for key in excessKeys {
                        self.usedNonces.remove(key)
                    }
                }
            }
            
            self.usedNonces.insert(key)
        }
    }
    
    /// Efface tous les nonces enregistrés
    public func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.usedNonces.removeAll()
        }
    }
    
    /// Vérifie et enregistre un nonce en une seule opération atomique
    /// - Parameters:
    ///   - nonce: Le nonce à vérifier et enregistrer
    ///   - jobId: L'ID du job associé au nonce
    /// - Returns: Vrai si le nonce était valide et a été enregistré, faux s'il était déjà utilisé
    public func useNonceIfValid(_ nonce: String, forJobId jobId: String) -> Bool {
        let key = "\(jobId):\(nonce)"
        
        return queue.sync(flags: .barrier) {
            if usedNonces.contains(key) {
                return false
            }
            
            // Si on atteint la taille maximale, on supprime les anciennes entrées
            if usedNonces.count >= windowSize {
                // On supprime les entrées les plus anciennes (les 10% les plus anciennes)
                let excessCount = usedNonces.count - Int(Double(windowSize) * 0.9)
                if excessCount > 0 {
                    let excessKeys = Array(usedNonces.prefix(excessCount))
                    for key in excessKeys {
                        usedNonces.remove(key)
                    }
                }
            }
            
            usedNonces.insert(key)
            return true
        }
    }
}

// MARK: - Extension pour l'intégration avec StratumClientNIO

extension ReplayProtection {
    /// Vérifie et enregistre une soumission complète
    /// - Parameters:
    ///   - jobId: L'ID du job
    ///   - extranonce2: L'extranonce2
    ///   - ntime: Le ntime
    ///   - nonce: Le nonce
    /// - Returns: Vrai si la soumission est valide, faux si c'est un rejeu
    public func validateAndRegisterSubmission(jobId: String, extranonce2: String, ntime: String, nonce: String) -> Bool {
        // Créer un identifiant unique pour cette soumission
        let submissionId = "\(jobId):\(extranonce2):\(ntime):\(nonce)"
        return useNonceIfValid(submissionId, forJobId: jobId)
    }
}
