import Foundation
import M1MinerShared

// MARK: - Conformité à StratumClientInterface

extension StratumClientNIO {
    
    // MARK: - Propriétés publiques
    
    /// La difficulté actuelle du travail
    public var currentDifficulty: Double {
        _stateLock.withLock {
            _currentJob?.difficulty ?? 0.0
        }
    }
    
    // MARK: - Méthodes d'authentification
    
    /// S'authentifie auprès du serveur
    /// - Parameters:
    ///   - worker: L'identifiant du worker
    ///   - password: Le mot de passe du worker
    ///   - completion: Callback appelé lorsque l'authentification est terminée
    public func authenticate(worker: String, password: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        logger.info("🔑 Authentification du worker: \(worker)")
        
        // Créer les paramètres de la requête
        let params: [Any] = [
            worker,  // worker_name
            password // password
        ]
        
        // Log des paramètres d'authentification
        logger.debug("🔍 mining.authorize params: \(params)")
        
        // Pour voir le JSON envoyé, on peut construire la requête comme dans sendRequest :
        let requestId = _stateLock.withLock { _requestIdCounter }
        let request = StratumRequest(id: requestId, method: "mining.authorize", params: params.map(AnyDecodable.init))
        do {
            let jsonData = try JSONEncoder().encode(request)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                logger.debug("🔍 mining.authorize JSON envoyé: \(jsonString)")
            }
        } catch {
            logger.warning("⚠️ Impossible d'encoder la requête mining.authorize en JSON: \(error)")
        }
        // Envoyer la requête
        sendRequest(method: "mining.authorize", params: params) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                // Vérifier si l'authentification a réussi
                if let isAuthorized = response.result?.value as? Bool {
                    if isAuthorized {
                        self.logger.info("✅ Authentification réussie")
                    } else {
                        self.logger.warning("⚠️ Authentification refusée")
                    }
                    completion(.success(isAuthorized))
                } else if let error = response.error {
                    self.logger.error("❌ Erreur d'authentification: \(error.message)")
                    completion(.failure(StratumError.serverError(code: error.code, message: error.message)))
                } else {
                    self.logger.error("❌ Réponse d'authentification inattendue")
                    completion(.failure(StratumError.invalidResponse("Réponse inattendue du serveur")))
                }
                
            case .failure(let error):
                self.logger.error("❌ Échec de l'authentification: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Méthodes de soumission (alias)
    
    /// Soumet une part au serveur (alias de submit)
    /// - Parameters:
    ///   - worker: L'identifiant du worker
    ///   - jobId: L'identifiant du travail
    ///   - nonce: Le nonce de la solution
    ///   - result: Le résultat du hachage
    ///   - completion: Callback appelé lorsque la soumission est terminée
    public func submitShare(worker: String, jobId: String, nonce: String, result: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        submit(worker: worker, jobId: jobId, nonce: nonce, result: result, completion: completion)
    }
}
