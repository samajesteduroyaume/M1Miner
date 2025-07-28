import Foundation
import NIO
import NIOConcurrencyHelpers
import Logging
import Network
import M1MinerShared

/// Classe principale du client Stratum utilisant NIO
public final class StratumClientNIO: StratumClientInterface {
    
    // MARK: - Propriétés publiques
    
    /// Délai maximum entre les tentatives de reconnexion (en secondes)
    private let maxReconnectDelay: TimeInterval = 300 // 5 minutes
    private let reconnectDelayLock = NIOLock()
    private var _reconnectDelayValue: TimeInterval = 1.0
    private var reconnectDelay: TimeInterval {
        get { reconnectDelayLock.withLock { _reconnectDelayValue } }
        set { reconnectDelayLock.withLock { _reconnectDelayValue = newValue } }
    }
    private var reconnectAttempts: Int = 0
    
    /// Délégué pour les événements du client
    public weak var delegate: StratumClientDelegate?
    
    // MARK: - Propriétés conformes à StratumClientInterface

    public var stats: ConnectionStats {
        // Version partagée : retourne une instance vide ou à adapter selon l'état réel
        return ConnectionStats()
    }
    
    public private(set) var isConnected: Bool {
        get { _stateLock.withLock { _isConnected } }
        set { 
            _stateLock.withLock { _isConnected = newValue }
            if newValue {
                onConnect?()
            } else {
                onDisconnect?(nil)
            }
        }
    }
    
    public internal(set) var currentJob: StratumJob? {
        get { _stateLock.withLock { _currentJob } }
        set { 
            _stateLock.withLock { _currentJob = newValue }
            if let job = newValue {
                onNewJob?(job)
            }
        }
    }
    
    // MARK: - Propriétés privées
    
    internal var _networkManager: NetworkManager?
    internal var _isConnected = false
    internal var _currentJob: StratumJob?
    internal var _pendingRequests = [UInt64: CallbackWrapper]()
    internal var _requestIdCounter: UInt64 = 1
    internal var _stateLock = NIOLock()
    internal var _reconnectTask: Task<Void, Never>?
    internal var _isConnecting = false
    
    // Callbacks
    public var onConnect: (() -> Void)?
    public var onDisconnect: ((Error?) -> Void)?
    public var onNewJob: ((StratumJob) -> Void)?
    public var onError: ((Error) -> Void)?
    
    // Logger
    internal let logger: Logger
    
    // MARK: - Initialisation
    
    public init(logger: Logger = Logger(label: "StratumClientNIO")) {
        self.logger = logger
    }
    
    deinit {
        _reconnectTask?.cancel()
        _reconnectTask = nil
        _networkManager?.disconnect()
    }
    
    // MARK: - Connexion
    
    public func connect(host: String, port: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Vérifier si déjà connecté
        if isConnected {
            completion(.success(()))
            return
        }
        
        // Marquer qu'une connexion est en cours
        _stateLock.withLock { _isConnecting = true }
        
        // Configurer le gestionnaire réseau
        setupNetworkManager(host: host, port: port)
        
        // Se connecter au serveur
        _networkManager?.connect(host: host, port: port) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success():
                self.isConnected = true
                self.reconnectAttempts = 0
                self.reconnectDelay = 1.0
                completion(.success(()))
                
            case .failure(let error):
                self.handleConnectionError(error, completion: completion)
            }
            
            self._stateLock.withLock { self._isConnecting = false }
        }
    }
    
    // Conformité au protocole StratumClientInterface (M1MinerShared)
    public func connect(host: String, port: Int, useTLS: Bool, workerName: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Appel de la connexion bas-niveau (TLS ignoré ici)
        self.connect(host: host, port: port) { [weak self] result in
            switch result {
            case .success:
                // Authentifier le worker après connexion
                self?.authenticate(worker: workerName, password: password) { authResult in
                    switch authResult {
                    case .success(let ok) where ok:
                        completion(.success(()))
                    case .success:
                        completion(.failure(StratumClientError.authenticationFailed("Refusé par le serveur")))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func disconnect() {
        _reconnectTask?.cancel()
        _reconnectTask = nil
        
        _networkManager?.disconnect()
        isConnected = false
    }
    
    // MARK: - Méthodes publiques
    
    public func submit(worker: String, jobId: String, nonce: String, result: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        logger.info("📤 Soumission de la part - Job: \(jobId), Nonce: \(nonce)")
        
        // Créer les paramètres de la requête
        let params: [Any] = [
            worker,  // worker_name
            jobId,   // job_id
            nonce,   // nonce
            result   // result
        ]
        
        // Envoyer la requête
        sendRequest(method: "mining.submit", params: params) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                // Vérifier si la soumission a été acceptée
                if let isAccepted = response.result?.value as? Bool {
                    if isAccepted {
                        self.logger.info("✅ Part acceptée - Job: \(jobId)")
                    } else {
                        self.logger.warning("⚠️ Part refusée - Job: \(jobId)")
                    }
                    completion(.success(isAccepted))
                } else if let error = response.error {
                    self.logger.error("❌ Erreur de soumission: \(error.message)")
                    // Le code d'erreur est déjà un Int, pas besoin de valeur par défaut
                    completion(.failure(StratumError.serverError(code: error.code, message: error.message)))
                } else {
                    self.logger.error("❌ Réponse de serveur inattendue")
                    completion(.failure(StratumError.invalidResponse("Réponse inattendue du serveur")))
                }
                
            case .failure(let error):
                self.logger.error("❌ Échec de la soumission: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Méthodes privées
    
    private func setupNetworkManager(host: String, port: Int) {
        // Créer un logger spécifique pour NetworkManager
        let networkLogger = Logger(label: "network.manager")
        _networkManager = NetworkManager(logger: networkLogger)
        _networkManager?.delegate = self
    }
    
    private func handleConnectionError(_ error: Error, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.error("❌ Échec de la connexion: \(error.localizedDescription)")
        
        // Planifier une tentative de reconnexion
        scheduleReconnect()
        
        // Appeler le callback d'échec
        completion(.failure(error))
    }
    
    internal func sendRequest(method: String, 
                           params: [Any] = [],
                           completion: @escaping (Result<StratumResponse, Error>) -> Void) {
        // Créer un identifiant unique pour cette requête
        let requestId = _stateLock.withLock {
            let id = _requestIdCounter
            _requestIdCounter += 1
            return id
        }
        
        // Créer la requête
        let request = StratumRequest(id: requestId, method: method, params: params.map(AnyDecodable.init))
        
        // Encoder la requête en JSON
        do {
            let jsonData = try JSONEncoder().encode(request)
            
            // Stocker le callback
            _stateLock.withLock {
                _pendingRequests[requestId] = CallbackWrapper(callback: completion)
            }
            
            // Planifier le timeout
            scheduleRequestTimeout(requestId: requestId, method: method, completion: completion)
            
            // Envoyer la requête
            _networkManager?.send(jsonData) { [weak self] result in
                switch result {
                case .failure(let error):
                    self?.handleRequestError(requestId: requestId, error: error)
                default:
                    break
                }
            }
            
        } catch {
            logger.error("❌ Échec de l'encodage de la requête: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    private func handleRequestError(requestId: UInt64, error: Error) {
        logger.error("❌ Erreur d'envoi de la requête: \(error.localizedDescription)")
        
        // Récupérer et supprimer le callback
        let callback = _stateLock.withLock { _pendingRequests.removeValue(forKey: requestId) }
        
        // Appeler le callback d'erreur
        callback?.callback(.failure(error))
    }
    
    private func scheduleRequestTimeout(requestId: UInt64, 
                                      method: String, 
                                      completion: @escaping (Result<StratumResponse, Error>) -> Void) {
        let timeoutTimer = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Vérifier si la requête est toujours en attente
            let wasPending = self._stateLock.withLock { self._pendingRequests.removeValue(forKey: requestId) } != nil
            
            if wasPending {
                self.logger.warning("⏱️ Timeout de la requête \(method) (ID: \(requestId))")
                completion(.failure(StratumError.timeout))
            }
        }
        
        // Planifier le timeout après 30 secondes
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutTimer)
    }
    
    private func scheduleReconnect() {
        // Vérifier si une reconnexion est déjà en cours de manière thread-safe
        let shouldReconnect = _stateLock.withLock { () -> Bool in
            if _isConnecting || isConnected {
                return false
            }
            _isConnecting = true
            return true
        }
        
        guard shouldReconnect else { return }
        
        // Annuler toute tâche de reconnexion existante
        _reconnectTask?.cancel()
        
        // Créer une nouvelle tâche de reconnexion
        _reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Attendre le délai de reconnexion
                try await Task.sleep(nanoseconds: UInt64(self.reconnectDelay * 1_000_000_000))
                
                // Vérifier si la tâche a été annulée
                try Task.checkCancellation()
                
                // Tenter de se reconnecter
                self.logger.info("🔄 Tentative de reconnexion (essai \(self.reconnectAttempts + 1))...")
                
                // Réinitialiser l'état de connexion
                self._stateLock.withLock { self._isConnecting = false }
                
                // Mettre à jour le délai pour la prochaine tentative (avec backoff exponentiel)
                self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
                self.reconnectAttempts += 1
                
            } catch {
                // La tâche a été annulée ou une erreur est survenue
                self._stateLock.withLock { self._isConnecting = false }
            }
        }
    }
}

// MARK: - NetworkManagerDelegate

extension StratumClientNIO: NetworkManagerDelegate {
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didConnectToHost host: String, port: Int) {
        logger.info("✅ Connecté avec succès à \(host):\(port)")
        isConnected = true
        reconnectAttempts = 0
        reconnectDelay = 1.0
    }
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didDisconnectWithError error: Error?) {
        if let error = error {
            logger.error("❌ Déconnecté avec erreur: \(error.localizedDescription)")
            onError?(error)
        } else {
            logger.info("ℹ️ Déconnecté du serveur")
        }
        
        isConnected = false
        
        // Planifier une reconnexion si nécessaire
        scheduleReconnect()
    }
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didReceiveData data: Data) {
        logger.debug("📥 Données reçues: \(data.count) octets")
        guard let rawString = String(data: data, encoding: .utf8) else {
            logger.error("❌ Données non décodables en UTF-8")
            return
        }
        for line in rawString.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else {
                logger.warning("⚠️ Ligne non décodable en UTF-8: \(trimmed)")
                continue
            }
            do {
                let response = try JSONDecoder().decode(StratumResponse.self, from: lineData)
                if let requestId = response.id {
                    let callback = _stateLock.withLock { _pendingRequests.removeValue(forKey: requestId) }
                    callback?.callback(.success(response))
                } else if let method = response.method, let params = response.params?.map({ $0.value }) {
                    handleNotification(method: method, params: params)
                }
            } catch {
                logger.error("❌ Ligne non JSON Stratum: \(trimmed) | Erreur: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Types internes

internal struct CallbackWrapper {
    let callback: (Result<StratumResponse, Error>) -> Void
}
