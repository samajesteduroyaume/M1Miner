import Logging

// Extension utilitaire pour logger les erreurs
extension Logger {
    func errorMessage(_ message: String) -> Logger.Message {
        return Logger.Message(stringLiteral: message)
    }
    
    func errorMessage(_ error: Error) -> Logger.Message {
        return Logger.Message(stringLiteral: "❌ \(error.localizedDescription)")
    }
    
    func error(_ message: String) {
        self.error(Logger.Message(stringLiteral: message))
    }
    
    func error(_ error: Error) {
        self.error(Logger.Message(stringLiteral: "❌ \(error.localizedDescription)"))
    }
}
