import Foundation
import Logging
import M1MinerShared
// Les types partagés sont déjà accessibles via M1MinerShared

// MARK: - Gestion des notifications

extension StratumClientNIO {
    
    /// Gère les notifications reçues du serveur
    /// - Parameters:
    ///   - method: Méthode de la notification
    ///   - params: Paramètres de la notification
    func handleNotification(method: String, params: [Any]) {
        logger.debug("📢 Notification reçue: \(method)")
        
        switch method {
        case "mining.notify":
            handleNewJobNotification(params: params)
        case "mining.set_difficulty":
            handleSetDifficultyNotification(params: params)
        case "mining.set_extranonce":
            handleSetExtranonceNotification(params: params)
        case "mining.set_target":
            handleSetTargetNotification(params: params)
        default:
            logger.warning("⚠️ Notification non gérée: \(method)")
        }
    }
    
    /// Gère la notification de nouveau travail
    /// - Parameter params: Paramètres de la notification
    fileprivate func handleNewJobNotification(params: [Any]) {
        logger.debug("🔄 Nouveau travail reçu")
        
        // Vérifie le nombre de paramètres (zpool envoie souvent 10 ou plus)
        guard params.count >= 9 else {
            logger.error("❌ Nombre de paramètres insuffisant pour mining.notify (\(params.count)): \(params)")
            return
        }
        
        // Extraction robuste des paramètres, gestion cas zpool
        let jobId = params[0] as? String ?? ""
        let previousHash = params[1] as? String ?? ""
        let coinbase1 = params[2] as? String ?? ""
        let coinbase2 = params[3] as? String ?? ""
        // zpool peut envoyer merkleBranches comme string unique ou tableau
        let merkleBranches: [String]
        if let arr = params[4] as? [String] {
            merkleBranches = arr
        } else if let single = params[4] as? String {
            merkleBranches = [single]
        } else {
            logger.warning("⚠️ Format inattendu pour merkleBranches: \(params[4])")
            merkleBranches = []
        }
        let version = params[5] as? String ?? ""
        let nbits = params[6] as? String ?? ""
        let ntime = params[7] as? String ?? ""
        let cleanJobs = params[8] as? Bool ?? false
        // Paramètres additionnels spécifiques pool : loggés pour debug
        if params.count > 9 {
            logger.info("ℹ️ Paramètres additionnels mining.notify (zpool): \(Array(params[9...]))")
        }
        // Création du job comme avant
        
        // Créer un nouveau travail
        let job = StratumJob(
            jobId: jobId,
            prevHash: previousHash,
            coinbase1: coinbase1,
            coinbase2: coinbase2,
            merkleBranches: merkleBranches,
            version: version,
            nBits: nbits,
            nTime: ntime,
            cleanJobs: cleanJobs,
            extranonce1: "", // À définir correctement
            extranonce2Size: 4 // Taille par défaut
        )
        
        // Mettre à jour le travail actuel
        currentJob = job
    }
    
    /// Gère la notification de changement de difficulté
    /// - Parameter params: Paramètres de la notification
    private func handleSetDifficultyNotification(params: [Any]) {
        logger.debug("📊 Changement de difficulté reçu")
        
        // Vérifier que nous avons un paramètre de difficulté
        guard params.count >= 1, let difficulty = params[0] as? Double else {
            logger.error("❌ Paramètre de difficulté manquant ou invalide")
            return
        }
        
        logger.info("🎚️ Nouvelle difficulté: \(difficulty)")
        
        // La difficulté est calculée à partir de nBits dans StratumJob
        // Pas besoin de la mettre à jour manuellement
        logger.info("🎚️ Nouvelle difficulté: \(difficulty) (basé sur nBits)")
    }
    
    /// Gère la notification de changement d'extranonce
    /// - Parameter params: Paramètres de la notification
    private func handleSetExtranonceNotification(params: [Any]) {
        logger.debug("🔄 Changement d'extranonce reçu")
        
        // Vérifier que nous avons suffisamment de paramètres
        guard params.count >= 1, let extranonce = params[0] as? String else {
            logger.error("❌ Paramètre extranonce manquant ou invalide")
            return
        }
        
        logger.info("🔑 Nouvel extranonce: \(extranonce)")
        
        // Mettre à jour l'extranonce1 du travail actuel si disponible
        _stateLock.withLock {
            if let job = _currentJob {
                // Créer une nouvelle instance avec l'extranonce mis à jour
                _currentJob = StratumJob(
                    jobId: job.jobId,
                    prevHash: job.prevHash,
                    coinbase1: job.coinbase1,
                    coinbase2: job.coinbase2,
                    merkleBranches: job.merkleBranches,
                    version: job.version,
                    nBits: job.nBits,
                    nTime: job.nTime,
                    cleanJobs: job.cleanJobs,
                    extranonce1: extranonce,
                    extranonce2Size: job.extranonce2Size,
                    target: job.target,
                    ghostRiderData: job.ghostRiderData
                )
            }
        }
    }
}
