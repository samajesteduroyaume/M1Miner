import Foundation

extension Data {
    /// Initialise un objet Data à partir d'une chaîne hexadécimale
    /// - Parameter hexString: Chaîne hexadécimale (peut inclure le préfixe "0x")
    init?(hexString: String) {
        var hexString = hexString.lowercased()
        
        // Supprimer le préfixe "0x" s'il existe
        if hexString.hasPrefix("0x") {
            hexString = String(hexString.dropFirst(2))
        }
        
        // Vérifier que la chaîne a une longueur paire
        guard hexString.count % 2 == 0 else { return nil }
        
        // Vérifier que la chaîne ne contient que des caractères hexadécimaux
        let hexChars = Set("0123456789abcdef")
        guard hexString.allSatisfy({ hexChars.contains($0) }) else { return nil }
        
        // Convertir la chaîne hexadécimale en données binaires
        var data = Data()
        var index = hexString.startIndex
        
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let byteString = hexString[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        
        self = data
    }
    
    /// Convertit les données en une chaîne hexadécimale
    /// - Returns: Une chaîne hexadécimale représentant les données
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Propriété d'aide pour accéder aux octets sous forme de tableau d'UInt8
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

extension Array where Element == UInt8 {
    /// Convertit un tableau d'octets en objet Data
    var data: Data {
        return Data(self)
    }
    
    /// Convertit un tableau d'octets en chaîne hexadécimale
    func toHexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
