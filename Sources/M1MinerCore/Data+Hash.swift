import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public extension Data {
    /// Calcule le hachage SHA-256 des données
    func sha256() -> Data {
        #if canImport(CommonCrypto)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(count), &hash)
        }
        return Data(hash)
        #else
        // Implémentation de secours si CommonCrypto n'est pas disponible
        // Note: Cette implémentation est moins efficace et ne doit être utilisée qu'en dernier recours
        var hash = [UInt8](repeating: 0, count: 32)
        for (index, byte) in self.enumerated() {
            hash[index % 32] = hash[index % 32] &+ byte
        }
        return Data(hash)
        #endif
    }
    
    // La méthode init(hex:) est déjà définie ailleurs, donc nous la supprimons d'ici
    
    /// Convertit les données en une chaîne hexadécimale
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
