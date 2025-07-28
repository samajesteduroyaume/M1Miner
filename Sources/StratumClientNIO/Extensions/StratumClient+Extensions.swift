import Foundation

// MARK: - Extensions utilitaires

extension Dictionary where Key == String {
    /// Accède de manière sécurisée à une valeur dans le dictionnaire avec un type spécifique
    func value<T>(forKey key: String, as type: T.Type) -> T? {
        guard let value = self[key] else { return nil }
        
        if let typedValue = value as? T {
            return typedValue
        }
        
        if let stringValue = value as? String, let typedValue = stringValue as? T {
            return typedValue
        }
        
        if let numberValue = value as? NSNumber {
            switch T.self {
            case is Int.Type: return numberValue.intValue as? T
            case is Int8.Type: return numberValue.int8Value as? T
            case is Int16.Type: return numberValue.int16Value as? T
            case is Int32.Type: return numberValue.int32Value as? T
            case is Int64.Type: return numberValue.int64Value as? T
            case is UInt.Type: return numberValue.uintValue as? T
            case is UInt8.Type: return numberValue.uint8Value as? T
            case is UInt16.Type: return numberValue.uint16Value as? T
            case is UInt32.Type: return numberValue.uint32Value as? T
            case is UInt64.Type: return numberValue.uint64Value as? T
            case is Float.Type: return numberValue.floatValue as? T
            case is Double.Type: return numberValue.doubleValue as? T
            case is Bool.Type: return numberValue.boolValue as? T
            default: break
            }
        }
        
        return nil
    }
}

// MARK: - Extensions pour AnyDecodable

// Suppression de l'extension problématique car AnyDecodable est déjà fourni par le module M1MinerShared
// et les méthodes d'accès à la valeur sont déjà disponibles via la propriété 'value' du protocole

// MARK: - Extensions pour les logs

extension Logger {
    /// Crée un logger avec un identifiant spécifique
    /// - Parameter identifier: Identifiant du logger
    /// - Returns: Une instance de Logger configurée
    static func createLogger(identifier: String) -> Logger {
        var logger = Logger(label: identifier)
        logger.logLevel = .debug
        return logger
    }
}

// MARK: - Extensions pour les erreurs

extension Error {
    /// Obtient un message d'erreur détaillé
    var detailedDescription: String {
        if let stratumError = self as? StratumError {
            return stratumError.localizedDescription
        }
        return localizedDescription
    }
}

// MARK: - Extensions pour les données

extension Data {
    /// Convertit les données en une chaîne hexadécimale
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Initialise les données à partir d'une chaîne hexadécimale
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        
        self = data
    }
}
