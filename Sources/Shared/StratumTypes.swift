import Foundation

/// Wrapper pour les callbacks des requêtes Stratum
public final class CallbackWrapper {
    public typealias CallbackType = (Result<StratumResponse, Error>) -> Void
    
    public let callback: CallbackType
    public let timeout: TimeInterval
    public let creationTime: Date
    
    public init(callback: @escaping CallbackType, timeout: TimeInterval) {
        self.callback = callback
        self.timeout = timeout
        self.creationTime = Date()
    }
}
