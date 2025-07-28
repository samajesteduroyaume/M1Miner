import Foundation
import Security

/// Gestion sécurisée du stockage des informations sensibles
public final class SecureStorage {
    // Service identifier for keychain
    private static let serviceName = "com.stratumclient.securestorage"
    
    /// Stocke une donnée sensible de manière sécurisée
    /// - Parameters:
    ///   - data: Les données à stocker
    ///   - key: La clé pour accéder aux données
    /// - Throws: Une erreur si l'opération échoue
    public static func store(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        // Supprimer d'abord toute entrée existante
        SecItemDelete(query as CFDictionary)
        
        // Ajouter la nouvelle entrée
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.storeFailed(status: status)
        }
    }
    
    /// Récupère des données stockées de manière sécurisée
    /// - Parameter key: La clé des données à récupérer
    /// - Returns: Les données si elles existent
    /// - Throws: Une erreur si l'opération échoue
    public static func retrieveData(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStorageError.retrievalFailed(status: status)
        }
    }
    
    /// Supprime des données stockées de manière sécurisée
    /// - Parameter key: La clé des données à supprimer
    /// - Throws: Une erreur si l'opération échoue
    public static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.deletionFailed(status: status)
        }
    }
    
    /// Vérifie si une clé existe dans le stockage sécurisé
    /// - Parameter key: La clé à vérifier
    /// - Returns: Vrai si la clé existe
    public static func contains(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    
    // MARK: - Extensions pour les types courants
    
    public static func store(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw SecureStorageError.stringConversionFailed
        }
        try store(data, forKey: key)
    }
    
    public static func retrieveString(forKey key: String) throws -> String? {
        guard let data = try retrieveData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Erreurs
    
    public enum SecureStorageError: LocalizedError {
        case storeFailed(status: OSStatus)
        case retrievalFailed(status: OSStatus)
        case deletionFailed(status: OSStatus)
        case stringConversionFailed
        
        public var errorDescription: String? {
            switch self {
            case .storeFailed(let status):
                return "Échec du stockage sécurisé. Code d'erreur: \(status)"
            case .retrievalFailed(let status):
                return "Échec de la récupération sécurisée. Code d'erreur: \(status)"
            case .deletionFailed(let status):
                return "Échec de la suppression sécurisée. Code d'erreur: \(status)"
            case .stringConversionFailed:
                return "Échec de la conversion de la chaîne en données"
            }
        }
    }
}

// MARK: - Extensions pour les types spécifiques à Stratum

extension SecureStorage {
    private static let workerNameKey = "stratum.workerName"
    private static let passwordKey = "stratum.password"
    
    /// Enregistre les informations d'identification de manière sécurisée
    public static func storeCredentials(workerName: String, password: String) throws {
        try store(workerName, forKey: workerNameKey)
        try store(password, forKey: passwordKey)
    }
    
    /// Récupère les informations d'identification de manière sécurisée
    public static func retrieveCredentials() throws -> (workerName: String, password: String)? {
        guard let workerName = try retrieveString(forKey: workerNameKey),
              let password = try retrieveString(forKey: passwordKey) else {
            return nil
        }
        return (workerName, password)
    }
    
    /// Supprime les informations d'identification stockées
    public static func deleteCredentials() throws {
        try delete(forKey: workerNameKey)
        try delete(forKey: passwordKey)
    }
}
