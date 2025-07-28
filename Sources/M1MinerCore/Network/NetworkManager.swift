import Foundation
import NIO
import NIOConcurrencyHelpers
import Atomics
import NIOSSL
import NIOTLS
import Logging

/// Stratégie de nouvelle tentative de connexion
public enum RetryStrategy: Equatable {
    case none
    case `repeat`(times: Int)
    case fixedDelay(maxRetries: Int, delay: TimeInterval)
    case exponentialBackoff(maxRetries: Int, initialDelay: TimeInterval, maxDelay: TimeInterval)
    
    public static func == (lhs: RetryStrategy, rhs: RetryStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.fixedDelay(lhsRetries, lhsDelay), .fixedDelay(rhsRetries, rhsDelay)):
            return lhsRetries == rhsRetries && lhsDelay == rhsDelay
        case let (.exponentialBackoff(lhsMaxRetries, lhsInitialDelay, lhsMaxDelay), .exponentialBackoff(rhsMaxRetries, rhsInitialDelay, rhsMaxDelay)):
            return lhsMaxRetries == rhsMaxRetries && lhsInitialDelay == rhsInitialDelay && lhsMaxDelay == rhsMaxDelay
        case let (.repeat(lhsTimes), .repeat(rhsTimes)):
            return lhsTimes == rhsTimes
        default:
            return false
        }
    }
    
    public func nextDelay(retryCount: Int) -> TimeInterval? {
        guard retryCount < maxRetries else { return nil }
        
        switch self {
        case .none:
            return nil
        case .fixedDelay(_, let delay):
            return delay
        case .exponentialBackoff(_, let initialDelay, let maxDelay):
            let delay = min(initialDelay * pow(2.0, Double(retryCount)), maxDelay)
            let jitter = Double.random(in: 0.8...1.2) // Ajout d'un facteur aléatoire
            return min(delay * jitter, maxDelay)
        case .repeat:
            return nil
        }
    }
    
    public var maxRetries: Int {
        switch self {
        case .none: return 0
        case .fixedDelay(let maxRetries, _): return maxRetries
        case .exponentialBackoff(let maxRetries, _, _): return maxRetries
        case .repeat(let times): return times
        }
    }
}

/// Configuration du gestionnaire réseau
public struct NetworkManagerConfiguration {
    public let host: String
    public let port: Int
    public let useTLS: Bool
    public let connectionTimeout: TimeInterval
    public let requestTimeout: TimeInterval
    public let maxRetryAttempts: Int
    public let retryDelay: TimeInterval
    public let keepAliveInterval: TimeInterval
    public let enableKeepAlive: Bool
    public let maxFrameSize: Int
    public var tlsConfiguration: TLSConfiguration?
    public var connectionRetryStrategy: RetryStrategy
    
    public init(
        host: String,
        port: Int,
        useTLS: Bool = false,
        connectionTimeout: TimeInterval = 10.0,
        requestTimeout: TimeInterval = 30.0,
        maxRetryAttempts: Int = 5,
        retryDelay: TimeInterval = 5.0,
        keepAliveInterval: TimeInterval = 120.0,
        enableKeepAlive: Bool = true,
        maxFrameSize: Int = 1_048_576, // 1MB
        tlsConfiguration: TLSConfiguration? = nil,
        connectionRetryStrategy: RetryStrategy = .exponentialBackoff(maxRetries: 5, initialDelay: 1.0, maxDelay: 60.0)
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.connectionTimeout = connectionTimeout
        self.requestTimeout = requestTimeout
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
        self.keepAliveInterval = keepAliveInterval
        self.enableKeepAlive = enableKeepAlive
        self.maxFrameSize = maxFrameSize
        self.tlsConfiguration = tlsConfiguration
        self.connectionRetryStrategy = connectionRetryStrategy
    }
}

// MARK: - NetworkMetrics

private struct NetworkMetrics {
    let bytesSent = ManagedAtomic<Int>(0)
    let bytesReceived = ManagedAtomic<Int>(0)
    let messagesSent = ManagedAtomic<Int>(0)
    let messagesReceived = ManagedAtomic<Int>(0)
    let connectionAttempts = ManagedAtomic<Int>(0)
    let connectionFailures = ManagedAtomic<Int>(0)
}

// MARK: - DateProvider Protocol

private protocol DateProvider {
    func now() -> Date
}

// MARK: - DefaultDateProvider

private struct DefaultDateProvider: DateProvider {
    func now() -> Date {
        return Date()
    }
}

// MARK: - ConnectionState

private enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

// MARK: - RequestContext

private struct RequestContext {
    let promise: EventLoopPromise<Data>
    let timeoutTask: Scheduled<Void>?
    
    init(promise: EventLoopPromise<Data>, timeoutTask: Scheduled<Void>?) {
        self.promise = promise
        self.timeoutTask = timeoutTask
    }
}

// MARK: - NetworkManager

/// Gestionnaire de connexion réseau optimisé pour le protocole Stratum
public final class NetworkManager {
    // MARK: - Configuration
    
    /// Configuration du gestionnaire réseau
    public let configuration: NetworkManagerConfiguration
    
    // MARK: - Propriétés
    
    private let logger: Logger
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var isShuttingDown = false
    private let stateLock = NIOLock()
    private var connectionState: ConnectionState = .disconnected
    private var retryCount = 0
    private var retryTimer: Scheduled<Void>?
    private var keepAliveTimer: RepeatedTask?
    private var pendingRequests = [UInt64: RequestContext]()
    private var nextRequestId: UInt64 = 1
    
    private let metrics = NetworkMetrics()
    private let dateProvider: DateProvider
    
    private let host: String
    private let port: Int
    
    private let pendingRequestsLock = NIOLock()
    private let messageQueueLock = NIOLock()
    
    // File d'attente pour le batching
    private var messageQueue: [NetworkMessage] = []
    private var isProcessingQueue = false
    
    // Délégation
    public weak var delegate: NetworkManagerDelegate?
    
    // MARK: - Initialisation
    
    public init(
        host: String,
        port: Int,
        configuration: NetworkManagerConfiguration? = nil,
        logger: Logger = Logger(label: "com.m1miner.network")
    ) {
        // Utiliser la configuration fournie ou en créer une nouvelle avec les paramètres par défaut
        self.configuration = configuration ?? NetworkManagerConfiguration(
            host: host,
            port: port,
            useTLS: false,
            connectionTimeout: 10.0,
            requestTimeout: 30.0,
            maxRetryAttempts: 5,
            retryDelay: 5.0,
            keepAliveInterval: 120.0,
            enableKeepAlive: true,
            maxFrameSize: 1_048_576,
            tlsConfiguration: nil,
            connectionRetryStrategy: .exponentialBackoff(maxRetries: 5, initialDelay: 1.0, maxDelay: 60.0)
        )
        self.host = host
        self.port = port
        self.logger = logger
        // La configuration est déjà initialisée avec les valeurs par défaut si nécessaire
        self.dateProvider = DefaultDateProvider()
    }
    
    // MARK: - Types internes
    
    private enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }
    
    private struct RequestContext {
        let promise: EventLoopPromise<Data>
        let timeoutTask: Scheduled<Void>?
        
        init(promise: EventLoopPromise<Data>, timeoutTask: Scheduled<Void>?) {
            self.promise = promise
            self.timeoutTask = timeoutTask
        }
    }
    
    // Structure pour les messages en file d'attente
    private struct NetworkMessage {
        let id: UInt64
        let data: Data
        let promise: EventLoopPromise<Data>?
        
        init(id: UInt64, data: Data, promise: EventLoopPromise<Data>?) {
            self.id = id
            self.data = data
            self.promise = promise
        }
    }
    
    // MARK: - Cycle de vie
    
    deinit {
        disconnect()
    }
    
    // MARK: - Logging
    
    private func logInitialization() {
        logger.info("Initialisation du gestionnaire réseau", metadata: [
            "host": .string(host),
            "port": .stringConvertible(port),
            "tls": .stringConvertible(configuration.useTLS)
        ])
    }
    
    // MARK: - Méthodes publiques
    
    /// Se connecte au serveur
    public func connect() -> EventLoopFuture<Void> {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        // Créer un nouvel EventLoopGroup si nécessaire
        if eventLoopGroup == nil {
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
        
        guard connectionState == .disconnected else {
            return MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
                .makeFailedFuture(NetworkError.invalidState)
        }
        
        guard let eventLoopGroup = eventLoopGroup else {
            return MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
                .makeFailedFuture(NetworkError.invalidState)
        }
        
        connectionState = .connecting
        isShuttingDown = false
        
        let eventLoop = eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)
        
        // Démarrer la connexion
        connectWithRetry(promise: promise, eventLoop: eventLoop)
        
        return promise.futureResult
    }
    
    private func connectWithRetry(promise: EventLoopPromise<Void>, eventLoop: EventLoop) {
        guard !isShuttingDown else {
            promise.fail(NetworkError.shuttingDown)
            return
        }
        
        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
                guard let self = self else { return channel.eventLoop.makeFailedFuture(NetworkError.deallocated) }
                
                var handlers: [ChannelHandler] = []
                
                // Ajouter le gestionnaire de timeout de lecture
                handlers.append(IdleStateHandler(
                    readTimeout: .seconds(Int64(self.configuration.connectionTimeout)),
                    writeTimeout: .seconds(Int64(self.configuration.requestTimeout))
                ))
                
                // Ajouter le codec de trame
                handlers.append(ByteToMessageHandler(ByteBufferToStringHandler()))
                
                // Ajouter le gestionnaire de protocole
                let handler = NetworkHandler(manager: self)
                handlers.append(handler)
                
                // Configurer TLS si nécessaire
                if self.configuration.useTLS, let tlsConfig = self.configuration.tlsConfiguration {
                    do {
                        let sslContext = try NIOSSLContext(configuration: tlsConfig)
                        let sslHandler = try NIOSSLClientHandler(
                            context: sslContext,
                            serverHostname: self.host
                        )
                        handlers.insert(sslHandler, at: 0)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                
                return channel.pipeline.addHandlers(handlers, position: .last)
            }
            .connectTimeout(.seconds(Int64(configuration.connectionTimeout)))
        
        // Démarrer la connexion
        let connectFuture = bootstrap.connect(host: host, port: port)
        
        connectFuture.whenSuccess { [weak self] channel in
            self?.connectionSucceeded(channel: channel, promise: promise)
        }
        
        connectFuture.whenFailure { [weak self] error in
            self?.connectionFailed(error: error, promise: promise)
        }
    }
    
    /// Se déconnecte du serveur
    public func disconnect() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard connectionState != .disconnected && connectionState != .disconnecting else {
            return
        }
        
        connectionState = .disconnecting
        isShuttingDown = true
        
        // Annuler les timers
        retryTimer?.cancel()
        retryTimer = nil
        
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        
        // Fermer le canal
        if let channel = self.channel {
            channel.close(mode: .all, promise: nil)
            self.channel = nil
        }
        
        // Fermer l'EventLoopGroup si nécessaire
        if let eventLoopGroup = self.eventLoopGroup {
            do {
                try eventLoopGroup.syncShutdownGracefully()
            } catch {
                logger.error("Erreur lors de l'arrêt de l'EventLoopGroup: \(error)")
            }
            self.eventLoopGroup = nil
        }
        
        // Échouer toutes les requêtes en attente
        failPendingRequests(NetworkError.connectionClosed)
        
    }



    private func connectionSucceeded(channel: Channel, promise: EventLoopPromise<Void>) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard connectionState == .connecting else {
            channel.close(mode: .all, promise: nil)
            promise.fail(NetworkError.invalidState)
            return
        }

        self.channel = channel
        connectionState = .connected
        retryCount = 0

        // Configurer le keep-alive si activé
        if configuration.enableKeepAlive {
            startKeepAliveTimer(eventLoop: channel.eventLoop)
        }

        // Traiter les messages en file d'attente
        processMessageQueue()

        promise.succeed(())

        logger.info("Connexion établie", metadata: [
            "local_address": .string("\(channel.localAddress?.description ?? "inconnu")"),
            "remote_address": .string("\(channel.remoteAddress?.description ?? "inconnu")")
        ])
    }

    private func connectionFailed(error: Error, promise: EventLoopPromise<Void>) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard connectionState == .connecting else {
            promise.fail(NetworkError.invalidState)
            return
        }

        logger.error("Échec de la connexion", metadata: [
            "error": .string(error.localizedDescription),
            "retry_count": .stringConvertible(retryCount)
        ])

        // Vérifier si nous devons réessayer
        let delay = configuration.connectionRetryStrategy.nextDelay(retryCount: retryCount)

        if let delay = delay, !isShuttingDown {
            retryCount += 1

            logger.notice("Nouvelle tentative dans \(delay) secondes...", metadata: [
                "retry_count": .stringConvertible(retryCount)
            ])

            retryTimer = eventLoopGroup?.next().scheduleTask(in: .seconds(Int64(delay))) { [weak self] in
                self?.connectWithRetry(promise: promise, eventLoop: promise.futureResult.eventLoop)
            }
        } else {
            connectionState = .disconnected
            promise.fail(NetworkError.connectionFailed(error))
        }
    }

    // MARK: - Gestion des requêtes en attente
    
    private func failPendingRequests(_ error: Error) {
        pendingRequestsLock.withLock {
            for (_, context) in pendingRequests {
                context.timeoutTask?.cancel()
                context.promise.fail(error)
            }
            pendingRequests.removeAll()
        }
    }
    
    // MARK: - Gestion du keep-alive
    
    private func startKeepAliveTimer(eventLoop: EventLoop) {
        keepAliveTimer?.cancel()
        
        keepAliveTimer = eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(Int64(configuration.keepAliveInterval)),
            delay: .seconds(Int64(configuration.keepAliveInterval))
        ) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    
    private func sendKeepAlive() {
        guard connectionState == .connected, let channel = channel else {
            return
        }
        
        // Envoyer un message de keep-alive vide
        let keepAliveMessage = "\n"
        var buffer = channel.allocator.buffer(capacity: keepAliveMessage.utf8.count)
        buffer.writeString(keepAliveMessage)
        
        channel.writeAndFlush(buffer).whenComplete { [weak self] result in
            switch result {
            case .success:
                self?.metrics.keepAliveSent.wrappingIncrement(ordering: .relaxed)
            case .failure(let error):
                self?.logger.error("Échec de l'envoi du keep-alive", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    // MARK: - Gestion des messages
    
    private func enqueueMessage(_ message: NetworkMessage) {
        messageQueueLock.withLock {
            messageQueue.append(message)
        }
        
        // Tenter de traiter la file d'attente
        processMessageQueue()
    }
    
    private func processMessageQueue() {
        messageQueueLock.lock()
        
        guard connectionState == .connected, let channel = channel, !isProcessingQueue else {
            messageQueueLock.unlock()
            return
        }
        
        isProcessingQueue = true
        messageQueueLock.unlock()
        
        func processNext() {
            messageQueueLock.lock()
            
            guard !messageQueue.isEmpty else {
                isProcessingQueue = false
                messageQueueLock.unlock()
                return
            }
            
            let message = messageQueue.removeFirst()
            messageQueueLock.unlock()
            
            sendData(message.data, requestId: message.id, promise: message.promise, channel: channel)
                .whenComplete { _ in
                    processNext()
                }
        }
        
        processNext()
    }

    private func sendData(_ data: Data, requestId: UInt64, promise: EventLoopPromise<Data>?, channel: Channel) -> EventLoopFuture<Void> {
        logger.debug("Envoi de données", metadata: ["bytes": "\(data.count)"])

        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        // Mettre à jour les métriques
        metrics.bytesSent.wrappingIncrement(by: data.count, ordering: .relaxed)
        metrics.messagesSent.wrappingIncrement(ordering: .relaxed)

        let writePromise = channel.eventLoop.makePromise(of: Void.self)
        channel.writeAndFlush(buffer, promise: writePromise)

        // Gérer la promesse de réponse
        if let promise = promise {
            pendingRequestsLock.withLock {
                pendingRequests[requestId] = RequestContext(
                    promise: promise,
                    timeoutTask: scheduleRequestTimeout(requestId: requestId, promise: promise)
                )
            }
        }

        writePromise.futureResult.whenFailure { [weak self] error in
            self?.logger.error("Échec de l'envoi des données", metadata: ["error": "\(error)"])
            promise?.fail(NetworkError.connectionFailed(error))
        }

        return writePromise.futureResult
    }

    /// Envoie une requête au serveur et retourne une promesse avec la réponse
    /// - Parameter data: Les données à envoyer
    /// - Returns: Une promesse qui sera résolue avec la réponse du serveur
    public func sendRequest(_ data: Data) -> EventLoopFuture<Data> {
        guard let eventLoopGroup = self.eventLoopGroup else {
            return eventLoopGroup?.next().makeFailedFuture(NetworkError.shuttingDown) ?? 
                   MultiThreadedEventLoopGroup(numberOfThreads: 1).next().makeFailedFuture(NetworkError.shuttingDown)
        }
        
        let promise = eventLoopGroup.next().makePromise(of: Data.self)
        
        guard let channel = self.channel else {
            promise.fail(NetworkError.notConnected)
            return promise.futureResult
        }
        
        let requestId = nextRequestId
        nextRequestId += 1
        
        // Planifier le timeout
        let timeoutTask = eventLoopGroup.next().scheduleTask(in: .seconds(Int64(configuration.requestTimeout))) { [weak self] in
            guard let self = self else { return }
            
            self.pendingRequestsLock.withLock {
                // Vérifier si la requête est toujours en attente
                if self.pendingRequests.removeValue(forKey: requestId) != nil {
                    self.metrics.errors.wrappingIncrement(ordering: .relaxed)
                    promise.fail(NetworkError.timeout)
                }
            }
        }
        
        // Stocker la requête en attente
        pendingRequestsLock.withLock {
            pendingRequests[requestId] = RequestContext(
                promise: promise,
                timeoutTask: timeoutTask
            )
        }
        
        // Envoyer les données
        _ = sendData(data, requestId: requestId, promise: promise, channel: channel)
        
        return promise.futureResult
    }
    
    // MARK: - Gestion des timeouts
    
    /// Planifie un timeout pour une requête
    /// - Parameters:
    ///   - requestId: L'ID de la requête
    ///   - promise: La promesse à compléter en cas de timeout
    /// - Returns: Une tâche planifiée qui peut être annulée
    private func scheduleRequestTimeout(requestId: UInt64, promise: EventLoopPromise<Data>) -> Scheduled<Void>? {
        guard let eventLoop = eventLoopGroup?.next() else { return nil }
        
        return eventLoop.scheduleTask(in: .seconds(Int64(configuration.requestTimeout))) { [weak self] in
            guard let self = self else { return }
            
            self.pendingRequestsLock.withLock {
                // Vérifier si la requête est toujours en attente
                if self.pendingRequests.removeValue(forKey: requestId) != nil {
                    self.metrics.errors.wrappingIncrement(ordering: .relaxed)
                    promise.fail(NetworkError.timeout)
                }
            }
        }
    }
    
    // MARK: - Gestion des réponses
    
    private func handleIncomingData(_ data: Data) {
        // Mettre à jour les métriques
        metrics.bytesReceived.wrappingIncrement(by: data.count, ordering: .relaxed)
        metrics.messagesReceived.wrappingIncrement(ordering: .relaxed)

        do {
            // Essayer de parser la réponse JSON
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw NetworkError.invalidResponse
            }

            // Extraire l'ID de la requête si présent
            if let requestId = json["id"] as? UInt64 {
                pendingRequestsLock.withLock {
                    if let context = pendingRequests.removeValue(forKey: requestId) {
                        // Annuler le timeout
                        context.timeoutTask?.cancel()

                        // Si c'est une réponse d'erreur
                        if let error = json["error"] as? [String: Any] {
                            let errorMsg = error["message"] as? String ?? "Unknown error"
                            context.promise.fail(NetworkError.connectionFailed(NSError(
                                domain: "Stratum",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: errorMsg]
                            )))
                        } else if let result = json["result"] {
                            // Si c'est une réponse réussie avec un résultat
                            do {
                                let resultData = try JSONSerialization.data(withJSONObject: result, options: [])
                                context.promise.succeed(resultData)
                            } catch {
                                context.promise.fail(NetworkError.invalidResponse)
                            }
                        } else {
                            // Réponse sans erreur ni résultat (peut être une notification)
                            context.promise.succeed(Data()) // Réponse vide pour les notifications
                        }
                    }
                }
            } else {
                // C'est probablement une notification (pas d'ID)
                delegate?.networkManager(self, didReceiveData: data)
            }
        } catch {
            logger.error("Erreur lors du traitement des données reçues", metadata: ["error": "\(error)"])
            metrics.errors.wrappingIncrement(ordering: .relaxed)
        }
    }


// MARK: - NetworkHandler

    private final class NetworkHandler: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        typealias OutboundOut = ByteBuffer
        
        private weak var manager: NetworkManager?
        private let logger: Logger
        
        init(manager: NetworkManager) {
            self.manager = manager
            self.logger = manager.logger
        }
        
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var buffer = unwrapInboundIn(data)
            
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                let data = Data(bytes: bytes, count: bytes.count)
                manager?.handleIncomingData(data)
            }
        }
        
        func errorCaught(context: ChannelHandlerContext, error: Error) {
            logger.error("Erreur de canal", metadata: [
                "error": .string(error.localizedDescription)
            ])
            
            // Fermer la connexion en cas d'erreur
            context.close(promise: nil)
        }
        
        func channelInactive(context: ChannelHandlerContext) {
            logger.info("Canal inactif")
            manager?.handleConnectionClosed()
        }
    }
    
    // MARK: - NetworkMetrics
    
    private struct NetworkMetrics {
        let bytesSent = ManagedAtomic<Int>(0)
        let bytesReceived = ManagedAtomic<Int>(0)
        let messagesSent = ManagedAtomic<Int>(0)
        let messagesReceived = ManagedAtomic<Int>(0)
        let errors = ManagedAtomic<Int>(0)
        let keepAliveSent = ManagedAtomic<Int>(0)
        
        mutating func reset() {
            bytesSent.store(0, ordering: .relaxed)
            bytesReceived.store(0, ordering: .relaxed)
            messagesSent.store(0, ordering: .relaxed)
            messagesReceived.store(0, ordering: .relaxed)
            errors.store(0, ordering: .relaxed)
        }
    }

}

// MARK: - NetworkError

public enum NetworkError: Error, Equatable {
    case alreadyConnected
    case notConnected
    case connectionFailed(Error)
    case connectionClosed
    case timeout
    case invalidState
    case invalidResponse
    case requestCancelled
    case shuttingDown
    case deallocated
    
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.alreadyConnected, .alreadyConnected):
            return true
        case (.notConnected, .notConnected):
            return true
        case (.connectionClosed, .connectionClosed):
            return true
        case (.timeout, .timeout):
            return true
        case (.invalidState, .invalidState):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.requestCancelled, .requestCancelled):
            return true
        case (.shuttingDown, .shuttingDown):
            return true
        case (.deallocated, .deallocated):
            return true
        case (.connectionFailed(let lhsError), .connectionFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - NetworkManager Extensions

extension NetworkManager {
    func handleConnectionClosed() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard connectionState != .disconnected else { return }
        
        connectionState = .disconnected
        channel = nil
        
        // Annuler le timer de keep-alive
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        
        // Échouer toutes les requêtes en attente
        failPendingRequests(NetworkError.connectionClosed)
        
        // Si nous ne sommes pas en train de nous arrêter, essayer de nous reconnecter
        if !isShuttingDown {
            logger.notice("Tentative de reconnexion...")
            
            // Réinitialiser l'EventLoopGroup
            if let eventLoopGroup = self.eventLoopGroup {
                do {
                    try eventLoopGroup.syncShutdownGracefully()
                } catch {
                    logger.error("Erreur lors de l'arrêt de l'EventLoopGroup: \(error)")
                }
                self.eventLoopGroup = nil
            }
            
            // Créer un nouvel EventLoopGroup
            self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            
            // Se reconnecter
            if let eventLoopGroup = self.eventLoopGroup {
                let eventLoop = eventLoopGroup.next()
                let promise = eventLoop.makePromise(of: Void.self)
                
                connectionState = .connecting
                connectWithRetry(promise: promise, eventLoop: eventLoop)
                
                promise.futureResult.whenFailure { [weak self] error in
                    self?.logger.error("Échec de la reconnexion: \(error)")
                }
            } else {
                logger.error("Impossible de se reconnecter: eventLoopGroup est nil")
            }
        }
    }
}

// MARK: - ByteBufferToStringHandler

private final class ByteBufferToStringHandler: ByteToMessageDecoder {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    
    private var buffer: ByteBuffer?
    
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Si nous n'avons pas de buffer, en créer un nouveau
        if self.buffer == nil {
            self.buffer = context.channel.allocator.buffer(capacity: buffer.readableBytes)
        }
        
        // Ajouter les données au buffer
        if var currentBuffer = self.buffer, buffer.readableBytes > 0 {
            // Lire toutes les données disponibles
            let readableBytes = buffer.readableBytes
            if let slice = buffer.readSlice(length: readableBytes) {
                // Créer une copie mutable de la slice
                var mutableSlice = slice
                currentBuffer.writeBuffer(&mutableSlice)
                self.buffer = currentBuffer
            } else {
                return .needMoreData
            }
        }
        
        return .needMoreData
    }
    
    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        // Traiter les données restantes
        if buffer.readableBytes > 0 {
            // Si nous avons des données en attente dans notre buffer, les ajouter d'abord
            if var currentBuffer = self.buffer, currentBuffer.readableBytes > 0 {
                // Lire les données disponibles
                let readableBytes = buffer.readableBytes
                if readableBytes > 0, var slice = buffer.readSlice(length: readableBytes) {
                    // Écrire les données dans le buffer actuel
                    currentBuffer.writeBuffer(&slice)
                    context.fireChannelRead(self.wrapInboundOut(currentBuffer))
                } else {
                    // Si aucune donnée n'est lue, utiliser le buffer actuel
                    context.fireChannelRead(self.wrapInboundOut(currentBuffer))
                }
            } else {
                context.fireChannelRead(self.wrapInboundOut(buffer))
            }
        } else if let currentBuffer = self.buffer, currentBuffer.readableBytes > 0 {
            // Si nous avons des données dans notre buffer mais plus dans le buffer d'entrée
            context.fireChannelRead(self.wrapInboundOut(currentBuffer))
        }
        
        // Réinitialiser le buffer pour la prochaine utilisation
        self.buffer = nil
        return .needMoreData
    }
}
