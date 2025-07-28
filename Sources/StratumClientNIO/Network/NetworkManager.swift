import Foundation
import NIO
import NIOConcurrencyHelpers
import Logging
import Network
import M1MinerShared

/// Gère la communication réseau avec le serveur Stratum
@available(macOS 10.15, *)
public final class NetworkManager: @unchecked Sendable, M1MinerShared.NetworkManager {
    // MARK: - Propriétés
    
    /// Délégé pour les événements réseau
    public weak var delegate: (any NetworkManagerDelegate)?
    
    /// Adaptateur pour gérer la compatibilité entre les protocoles
    private var adapter: NetworkManagerAdapter?
    
    /// Groupe d'événements pour NIO
    private var group: MultiThreadedEventLoopGroup?
    
    /// Canal de communication
    private var channel: Channel?
    
    /// File d'attente pour les callbacks
    private let callbackQueue = DispatchQueue(label: "com.m1miner.network.callbackQueue")
    
    /// Logger
    private let logger: Logger
    
    /// Verrou pour les opérations thread-safety
    private let lock = NIOLock()
    
    // MARK: - Initialisation
    
    /// Initialise un nouveau gestionnaire réseau
    /// - Parameter logger: Logger à utiliser pour les messages de débogage
    public init(logger: Logger) {
        self.logger = logger
        
        // Configurer l'adaptateur si un délégué est déjà défini
        // (utile si le délégué est défini avant l'initialisation)
        if let delegate = delegate {
            self.adapter = NetworkManagerAdapter(delegate: delegate, logger: logger)
        }
    }
    
    // MARK: - Connexion
    
    // MARK: - M1MinerShared.NetworkManager
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didConnectToHost host: String, port: Int) {
        logger.info("✅ Connecté avec succès à \(host):\(port)")
        delegate?.networkManager(self, didConnectToHost: host, port: port)
    }
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didDisconnectWithError error: Error?) {
        if let error = error {
            logger.error("❌ Déconnecté avec erreur: \(error.localizedDescription)")
        } else {
            logger.info("ℹ️ Déconnecté du serveur")
        }
        delegate?.networkManager(self, didDisconnectWithError: error)
    }
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didReceiveData data: Data) {
        logger.debug("📥 Données reçues: \(data.count) octets")
        delegate?.networkManager(self, didReceiveData: data)
    }
    
    public func networkManager(_ manager: any M1MinerShared.NetworkManager, didEncounterError error: Error) {
        logger.error("❌ Échec réseau: \(error.localizedDescription)")
        
        // Nettoyer les ressources en cas d'échec
        cleanup()
        
        // Notifier le délégué après le nettoyage
        delegate?.networkManager(self, didEncounterError: error)
    }
    
    // MARK: - Connexion
    
    /// Établit une connexion avec le serveur
    /// - Parameters:
    ///   - host: Hôte du serveur
    ///   - port: Port du serveur
    ///   - completion: Callback appelé lorsque la connexion est établie ou a échoué
    public func connect(host: String, port: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Vérifier si déjà connecté
        if channel != nil {
            completion(.failure(StratumError.connectionError("Déjà connecté")))
            return
        }
        
        // Mettre à jour l'état de connexion
        self.connectionState = .connecting
        
        // Configurer le groupe d'événements
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        // Créer un bootstrap pour la connexion
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
                guard let self = self else { return channel.eventLoop.makeFailedFuture(StratumError.connectionError("NetworkManager a été libéré")) }
                
                // Créer le handler de message
                let messageHandler = StratumMessageHandler(logger: self.logger, networkManager: self)
                
                // Ajouter le décodeur de messages Stratum et le handler
                return channel.pipeline.addHandler(ByteToMessageHandler(StratumMessageDecoder()))
                    .flatMap { _ in
                        channel.pipeline.addHandler(messageHandler)
                    }
            }
        
        // Établir la connexion
        bootstrap.connect(host: host, port: port).whenComplete { [weak self] (result: Result<Channel, Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let channel):
                self.lock.withLock {
                    self.channel = channel
                    self.connectionState = .connected
                }
                self.logger.info("✅ Connecté au serveur \(host):\(port)")
                self.networkManager(self, didConnectToHost: host, port: port)
                completion(.success(()))
                
            case .failure(let error):
                self.logger.error("❌ Échec de la connexion: \(error.localizedDescription)")
                let stratumError = StratumError.connectionFailed(error)
                self.connectionState = .disconnected
                self.networkManager(self, didEncounterError: stratumError)
                self.cleanup()
                completion(.failure(stratumError))
            }
        }
    }
    
    /// Ferme la connexion
    public func disconnect() {
        guard let channel = channel else { return }
        
        // Mettre à jour l'état de connexion
        self.connectionState = .disconnecting
        
        channel.close(mode: .all).whenComplete { [weak self] _ in
            guard let self = self else { return }
            self.cleanup()
            self.connectionState = .disconnected
            self.delegate?.networkManager(self, didDisconnectWithError: nil)
        }
    }
    
    /// Nettoie les ressources de manière thread-safe
    private func cleanup() {
        // Définir une fonction de nettoyage qui sera exécutée de manière synchrone
        let cleanupClosure = { [weak self] in
            guard let self = self else { return }
            
            // Verrouiller pour l'accès thread-safe
            self.lock.lock()
            defer { self.lock.unlock() }
            
            do {
                // Fermer le canal s'il existe
                if let channel = self.channel {
                    try channel.close(mode: .all).wait()
                    self.channel = nil
                    self.connectionState = .disconnected
                    self.logger.debug("✅ Canal de communication fermé avec succès")
                }
                
                // Arrêter le groupe d'événements s'il existe
                if let group = self.group {
                    try group.syncShutdownGracefully()
                    self.group = nil
                    self.connectionState = .disconnected
                    self.logger.debug("✅ Groupe d'événements arrêté avec succès")
                }
            } catch {
                self.logger.error("❌ Erreur lors du nettoyage: \(error.localizedDescription)")
            }
        }
        
        // Exécuter le nettoyage de manière synchrone
        cleanupClosure()
    }
    
    // MARK: - Envoi de données
    
    /// Envoie des données au serveur de manière thread-safe
    /// - Parameters:
    ///   - data: Données à envoyer
    ///   - completion: Callback appelé lorsque l'envoi est terminé ou a échoué
    public func send(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        // Vérifier la connexion de manière thread-safe
        let isChannelActive: Bool = lock.withLock {
            guard let channel = self.channel, channel.isActive else {
                return false
            }
            return true
        }
        
        // Si le canal n'est pas actif, signaler l'erreur
        guard isChannelActive, let channel = self.channel else {
            let error = StratumError.notConnected
            self.logger.error("❌ Impossible d'envoyer des données: Pas connecté au serveur")
            completion(.failure(error))
            self.delegate?.networkManager(self, didEncounterError: error)
            return
        }
        
        // Créer un buffer avec les données à envoyer
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        
        // Envoyer les données de manière asynchrone
        channel.writeAndFlush(buffer).whenComplete { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                self.logger.debug("📤 Données envoyées avec succès: \(data.count) octets")
                completion(.success(()))
                
            case .failure(let error):
                self.logger.error("❌ Échec de l'envoi des données: \(error.localizedDescription)")
                
                // Nettoyer les ressources en cas d'échec
                self.cleanup()
                
                // Créer et signaler l'erreur
                let stratumError = StratumError.networkError(error)
                self.delegate?.networkManager(self, didEncounterError: stratumError)
                completion(.failure(stratumError))
            }
        }
    }
    
    // MARK: - Propriétés utiles
    
    /// État actuel de la connexion (requis par M1MinerShared.NetworkManager)
    public private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            logger.debug("🔄 État de la connexion: \(connectionState)")
        }
    }
    
    /// Indique si le gestionnaire est connecté
    var isConnected: Bool {
        return channel?.isActive ?? false
    }
    
    // MARK: - Gestion des événements du StratumMessageHandler
    
    /// Gère les données reçues du serveur
    /// - Parameter data: Les données reçues
    internal func handleIncomingData(_ data: Data) {
        logger.debug("📥 Données reçues: \(data.count) octets")
        delegate?.networkManager(self, didReceiveData: data)
    }
    
    /// Gère les erreurs survenues lors de la communication
    /// - Parameter error: L'erreur survenue
    internal func handleError(_ error: Error) {
        logger.error("❌ Erreur réseau: \(error.localizedDescription)")
        delegate?.networkManager(self, didEncounterError: error)
    }
    
    /// Gère la déconnexion du serveur
    internal func handleDisconnection() {
        logger.info("ℹ️ Déconnecté du serveur")
        connectionState = .disconnected
        delegate?.networkManager(self, didDisconnectWithError: nil)
    }
}

// MARK: - Handlers NIO

/// Décode les messages Stratum entrants
private final class StratumMessageDecoder: ByteToMessageDecoder, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = Data
    
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes > 0 else {
            return .needMoreData
        }
        
        // Créer un Data à partir du ByteBuffer
        let slice = buffer.slice()
        var data = Data()
        if let bytes = slice.getBytes(at: slice.readerIndex, length: slice.readableBytes) {
            data = Data(bytes)
        }
        buffer.moveReaderIndex(to: buffer.writerIndex)
        context.fireChannelRead(wrapInboundOut(data))
        return .continue
    }
    
    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        return try decode(context: context, buffer: &buffer)
    }
}

/// Gère les messages Stratum entrants
private final class StratumMessageHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Data
    typealias OutboundOut = Data
    
    private let logger: Logger
    private weak var networkManager: NetworkManager?
    
    init(logger: Logger, networkManager: NetworkManager) {
        self.logger = logger
        self.networkManager = networkManager
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)
        
        // Transmettre les données au NetworkManager via l'event loop pour assurer la sécurité des threads
        context.eventLoop.execute { [weak self] in
            guard let self = self, let networkManager = self.networkManager else { return }
            // Utiliser la méthode appropriée du NetworkManager pour gérer les données reçues
            networkManager.handleIncomingData(data)
        }
        
        // Signaler que nous avons traité le message
        context.fireChannelReadComplete()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("❌ Erreur de canal: \(error.localizedDescription)")
        
        // Transmettre l'erreur au NetworkManager via l'event loop
        context.eventLoop.execute { [weak self] in
            guard let self = self, let networkManager = self.networkManager else { return }
            networkManager.handleError(error)
        }
        
        // Fermer la connexion en cas d'erreur de manière asynchrone
        context.eventLoop.execute {
            context.close(mode: .all, promise: nil)
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        logger.debug("🔌 Canal inactif")
        
        // Notifier le NetworkManager de la déconnexion
        context.eventLoop.execute { [weak self] in
            guard let self = self, let networkManager = self.networkManager else { return }
            networkManager.handleDisconnection()
        }
        
        // Appeler l'implémentation parente avant de fermer
        context.fireChannelInactive()
        
        // Fermer le canal de manière asynchrone
        context.eventLoop.execute {
            context.close(mode: .all, promise: nil)
        }
    }
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        // Gérer les événements utilisateur entrants si nécessaire
        if let idleEvent = event as? IdleStateHandler.IdleStateEvent {
            logger.debug("🕒 Événement d'inactivité: \(idleEvent)")
        }
        
        // Transmettre l'événement à la chaîne de handlers
        context.fireUserInboundEventTriggered(event)
    }
    
    // MARK: - Gestion du cycle de vie
    
    func handlerAdded(context: ChannelHandlerContext) {
        logger.debug("➕ Handler ajouté au pipeline")
    }
    
    func handlerRemoved(context: ChannelHandlerContext) {
        logger.debug("➖ Handler retiré du pipeline")
    }
}
