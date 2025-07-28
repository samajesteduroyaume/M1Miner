import NIO
import NIOSSL
import NIOPosix
import NIOCore
import NIOExtras
import Foundation

enum NetworkError: Error {
    case connectionFailed
    case invalidURL
    case sslError(Error)
    case connectionClosed
    case timeout
    case invalidResponse
}

class NetworkManager {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private var sslContext: NIOSSLContext?
    private let host: String
    private let port: Int
    private let useTLS: Bool
    
    // Gestion des messages entrants et déconnexions
    var onMessage: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    
    private var messageBuffer: [ByteBuffer] = []
    private var responseHandler: ((Result<Data, NetworkError>) -> Void)?
    private var isConnected = false
    private let timeout: TimeAmount
    private var timeoutTask: Scheduled<Void>?
    
    init(host: String, port: Int, useTLS: Bool = true, timeout: TimeAmount = .seconds(30)) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.timeout = timeout
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        if useTLS {
            do {
                self.sslContext = try NIOSSLContext(
                    configuration: TLSConfiguration.makeClientConfiguration()
                )
            } catch {
                print("Failed to create SSL context: \(error)")
            }
        }
    }
    
    deinit {
        disconnect()
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    func connect(completion: @escaping (Result<Void, NetworkError>) -> Void) {
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { [weak self] channel in
                guard let self = self else {
                    return channel.eventLoop.makeFailedFuture(NetworkError.connectionFailed)
                }
                
                var handlers: [ChannelHandler] = []
                
                // Add SSL handler if needed
                if self.useTLS, let sslContext = self.sslContext {
                    do {
                        let sslHandler = try NIOSSLClientHandler(
                            context: sslContext,
                            serverHostname: self.host
                        )
                        handlers.append(sslHandler)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(NetworkError.sslError(error))
                    }
                }
                
                // Add pipeline handlers
                let messageHandler = MessageHandler(networkManager: self)
                
                // Add the handlers one by one with explicit type annotations
                let frameDecoder = ByteToMessageHandler(LineBasedFrameDecoder())
                return channel.pipeline.addHandler(frameDecoder).flatMap {
                    channel.pipeline.addHandler(messageHandler, name: "messageHandler")
                }
            }
        
        let connectFuture = bootstrap.connect(host: host, port: port)
            .flatMap { [weak self] (channel: Channel) -> EventLoopFuture<Void> in
                guard let self = self else {
                    return channel.eventLoop.makeFailedFuture(NetworkError.connectionFailed)
                }
                
                self.channel = channel
                self.isConnected = true
                
                // Set up timeout
                self.setupTimeout()
                
                return channel.eventLoop.makeSucceededFuture(())
            }
        
        connectFuture.whenComplete { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                print("Connection error: \(error)")
                completion(.failure(.connectionFailed))
            }
        }
    }
    
    func disconnect() {
        timeoutTask?.cancel()
        timeoutTask = nil
        
        if let channel = channel {
            channel.close(mode: .all, promise: nil)
            self.channel = nil
        }
        
        isConnected = false
    }
    
    func send(_ data: Data, completion: @escaping (Result<Data, NetworkError>) -> Void) {
        guard isConnected, let channel = channel else {
            completion(.failure(.connectionClosed))
            return
        }
        
        responseHandler = completion
        
        // Reset timeout on new message
        setupTimeout()
        
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        
        let promise = channel.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { [weak self] result in
            if case .failure = result {
                self?.responseHandler?(.failure(.connectionClosed))
                self?.responseHandler = nil
            }
        }
        
        channel.writeAndFlush(buffer, promise: promise)
    }
    
    func send(_ string: String, completion: @escaping (Result<Data, NetworkError>) -> Void) {
        guard let data = string.data(using: .utf8) else {
            completion(.failure(.invalidResponse))
            return
        }
        
        send(data, completion: completion)
    }
    
    // MARK: - Private Methods
    
    private func setupTimeout() {
        timeoutTask?.cancel()
        
        guard let channel = channel else { return }
        
        timeoutTask = channel.eventLoop.scheduleTask(in: timeout) { [weak self] in
            guard let self = self else { return }
            
            self.responseHandler?(.failure(.timeout))
            self.responseHandler = nil
            self.disconnect()
        }
    }
    
    // MARK: - Message Handling
    
    func handleInboundData(_ data: Data) {
        timeoutTask?.cancel()
        
        if let handler = responseHandler {
            handler(.success(data))
            responseHandler = nil
        } else if let onMessage = onMessage {
            // Transmettre les messages non sollicités au gestionnaire de messages
            onMessage(data)
        } else {
            // Aucun gestionnaire de messages défini, journaliser le message non sollicité
            print("Received unsolicited data: \(String(data: data, encoding: .utf8) ?? "")")
        }
    }
}

// MARK: - Channel Handlers

private final class MessageHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private weak var networkManager: NetworkManager?
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            let data = Data(bytes: bytes, count: bytes.count)
            networkManager?.handleInboundData(data)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Network error: \(error)")
        context.close(promise: nil)
        networkManager?.disconnect()
        networkManager?.onDisconnect?()
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        networkManager?.disconnect()
        networkManager?.onDisconnect?()
        context.close(promise: nil)
    }
}
