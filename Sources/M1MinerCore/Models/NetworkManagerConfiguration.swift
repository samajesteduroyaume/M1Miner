import Foundation
import NIO
import NIOSSL

/// Configuration pour le NetworkManager
public struct NetworkManagerConfiguration {
    // MARK: - Propriétés
    
    public let host: String
    public let port: Int
    public let useTLS: Bool
    public let workerName: String
    public let password: String
    public let connectionTimeout: TimeInterval
    public let requestTimeout: TimeInterval
    public let maxRetryAttempts: Int
    public let retryDelay: TimeInterval
    public let keepAliveInterval: TimeInterval
    public let enableKeepAlive: Bool
    public let maxFrameSize: Int
    public let tlsConfiguration: TLSConfiguration?
    
    // MARK: - Initialisation
    
    public init(
        host: String,
        port: Int,
        useTLS: Bool,
        workerName: String = "",
        password: String = "",
        connectionTimeout: TimeInterval = 10.0,
        requestTimeout: TimeInterval = 30.0,
        maxRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 5.0,
        keepAliveInterval: TimeInterval = 30.0,
        enableKeepAlive: Bool = true,
        maxFrameSize: Int = 1_048_576, // 1MB
        tlsConfiguration: TLSConfiguration? = nil
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.workerName = workerName
        self.password = password
        self.connectionTimeout = connectionTimeout
        self.requestTimeout = requestTimeout
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
        self.keepAliveInterval = keepAliveInterval
        self.enableKeepAlive = enableKeepAlive
        self.maxFrameSize = maxFrameSize
        self.tlsConfiguration = tlsConfiguration
    }
}
