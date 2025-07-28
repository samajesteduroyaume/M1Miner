import Foundation

/// Représente un entier non signé de 256 bits utilisé pour les calculs de hachage
public struct UInt256: Equatable, Comparable {
    // Stocké en little-endian (octet le moins significatif en premier)
    private var parts: (UInt64, UInt64, UInt64, UInt64)
    
    // MARK: - Initialisation
    
    public init() {
        self.parts = (0, 0, 0, 0)
    }
    
    public init(_ value: UInt64) {
        self.parts = (value, 0, 0, 0)
    }
    
    public init(littleEndian data: Data) {
        assert(data.count >= 32, "UInt256 nécessite au moins 32 octets")
        
        let part0 = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self) }
        let part1 = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let part2 = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }
        let part3 = data.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt64.self) }
        
        self.parts = (part0, part1, part2, part3)
    }
    
    public init(bigEndian data: Data) {
        assert(data.count >= 32, "UInt256 nécessite au moins 32 octets")
        
        let part3 = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self) }.byteSwapped
        let part2 = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }.byteSwapped
        let part1 = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }.byteSwapped
        let part0 = data.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt64.self) }.byteSwapped
        
        self.parts = (part0, part1, part2, part3)
    }
    
    // MARK: - Propriétés
    
    public var isZero: Bool {
        return parts.0 == 0 && parts.1 == 0 && parts.2 == 0 && parts.3 == 0
    }
    
    // MARK: - Initialisation à partir d'une chaîne hexadécimale
    
    /// Initialise un UInt256 à partir d'une chaîne hexadécimale
    /// - Parameter hexString: Chaîne hexadécimale (avec ou sans le préfixe "0x")
    public init?(hexString: String) {
        var hexStr = hexString.lowercased()
        
        // Supprimer le préfixe "0x" si présent
        if hexStr.hasPrefix("0x") {
            hexStr = String(hexStr.dropFirst(2))
        }
        
        // Vérifier que la chaîne ne contient que des caractères hexadécimaux
        let hexChars = Set("0123456789abcdef")
        guard hexStr.allSatisfy({ hexChars.contains($0) }) else {
            return nil
        }
        
        // Remplir avec des zéros à gauche pour avoir une longueur paire (2 caractères par octet)
        let paddedHexStr = hexStr.count % 2 == 0 ? hexStr : "0" + hexStr
        
        // Convertir la chaîne hexadécimale en données binaires
        var data = Data()
        var index = paddedHexStr.startIndex
        
        while index < paddedHexStr.endIndex {
            let nextIndex = paddedHexStr.index(index, offsetBy: 2, limitedBy: paddedHexStr.endIndex) ?? paddedHexStr.endIndex
            let byteStr = String(paddedHexStr[index..<nextIndex])
            if let byte = UInt8(byteStr, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        
        // Remplir avec des zéros à gauche pour obtenir 32 octets
        while data.count < 32 {
            data.insert(0, at: 0)
        }
        
        // Tronquer à 32 octets si nécessaire (au cas où la chaîne était trop longue)
        if data.count > 32 {
            data = data.suffix(32)
        }
        
        // Initialiser à partir des données binaires (big-endian par défaut)
        self.init(bigEndian: data)
    }
    
    // MARK: - Conversion
    
    public var data: Data {
        var result = Data(count: 32)
        result.withUnsafeMutableBytes { ptr in
            let typedPtr = ptr.bindMemory(to: UInt64.self)
            typedPtr[0] = parts.0
            typedPtr[1] = parts.1
            typedPtr[2] = parts.2
            typedPtr[3] = parts.3
        }
        return result
    }
    
    public var hexString: String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Opérations de comparaison
    
    public static func == (lhs: UInt256, rhs: UInt256) -> Bool {
        return lhs.parts.0 == rhs.parts.0 &&
               lhs.parts.1 == rhs.parts.1 &&
               lhs.parts.2 == rhs.parts.2 &&
               lhs.parts.3 == rhs.parts.3
    }
    
    public static func < (lhs: UInt256, rhs: UInt256) -> Bool {
        if lhs.parts.3 != rhs.parts.3 { return lhs.parts.3 < rhs.parts.3 }
        if lhs.parts.2 != rhs.parts.2 { return lhs.parts.2 < rhs.parts.2 }
        if lhs.parts.1 != rhs.parts.1 { return lhs.parts.1 < rhs.parts.1 }
        return lhs.parts.0 < rhs.parts.0
    }
    
    // MARK: - Opérations arithmétiques
    
    /// Divise un UInt256 par un Double et retourne un UInt256
    /// - Parameters:
    ///   - lhs: Le dividende UInt256
    ///   - rhs: Le diviseur Double
    /// - Returns: Le quotient UInt256
    public static func / (lhs: UInt256, rhs: Double) -> UInt256 {
        // Vérifier que le diviseur n'est pas zéro
        guard !rhs.isZero else {
            fatalError("Division par zéro")
        }
        
        // Convertir le UInt256 en Double (peut perdre en précision pour les très grands nombres)
        // C'est une approximation, mais suffisante pour le calcul de la difficulté
        let lhsDouble = Double(lhs.parts.3) * pow(2.0, 192.0) +
                       Double(lhs.parts.2) * pow(2.0, 128.0) +
                       Double(lhs.parts.1) * pow(2.0, 64.0) +
                       Double(lhs.parts.0)
        
        let resultDouble = lhsDouble / rhs
        
        // Convertir le résultat en UInt256
        guard resultDouble <= Double(UInt64.max) else {
            // Si le résultat est trop grand, retourner la valeur maximale
            return UInt256(UInt64.max, UInt64.max, UInt64.max, UInt64.max)
        }
        
        let uint64Value = UInt64(resultDouble)
        return UInt256(uint64Value)
    }
    
    public static func + (lhs: UInt256, rhs: UInt256) -> UInt256 {
        var result = UInt256()
        var carry: UInt64 = 0
        
        let (sum0, carry0) = lhs.parts.0.addingReportingOverflow(rhs.parts.0)
        result.parts.0 = sum0
        carry = carry0 ? 1 : 0
        
        let (sum1, carry1) = lhs.parts.1.addingReportingOverflow(rhs.parts.1)
        let (sum1WithCarry, carry1a) = sum1.addingReportingOverflow(carry)
        result.parts.1 = sum1WithCarry
        carry = (carry1 || carry1a) ? 1 : 0
        
        let (sum2, carry2) = lhs.parts.2.addingReportingOverflow(rhs.parts.2)
        let (sum2WithCarry, carry2a) = sum2.addingReportingOverflow(carry)
        result.parts.2 = sum2WithCarry
        carry = (carry2 || carry2a) ? 1 : 0
        
        let (sum3, _) = lhs.parts.3.addingReportingOverflow(rhs.parts.3)
        result.parts.3 = sum3 &+ carry
        
        return result
    }
    
    public static func & (lhs: UInt256, rhs: UInt256) -> UInt256 {
        return UInt256(lhs.parts.0 & rhs.parts.0,
                      lhs.parts.1 & rhs.parts.1,
                      lhs.parts.2 & rhs.parts.2,
                      lhs.parts.3 & rhs.parts.3)
    }
    
    public static func | (lhs: UInt256, rhs: UInt256) -> UInt256 {
        return UInt256(lhs.parts.0 | rhs.parts.0,
                      lhs.parts.1 | rhs.parts.1,
                      lhs.parts.2 | rhs.parts.2,
                      lhs.parts.3 | rhs.parts.3)
    }
    
    public static func ^ (lhs: UInt256, rhs: UInt256) -> UInt256 {
        return UInt256(lhs.parts.0 ^ rhs.parts.0,
                      lhs.parts.1 ^ rhs.parts.1,
                      lhs.parts.2 ^ rhs.parts.2,
                      lhs.parts.3 ^ rhs.parts.3)
    }
    
    public static prefix func ~ (value: UInt256) -> UInt256 {
        return UInt256(~value.parts.0, ~value.parts.1, ~value.parts.2, ~value.parts.3)
    }
    
    // MARK: - Décalages
    
    public static func << (lhs: UInt256, rhs: UInt256) -> UInt256 {
        // Simplification: on suppose que le décalage est petit (< 64)
        guard rhs < UInt256(64) else { return UInt256() }
        let shift = Int(rhs.parts.0)
        
        var result = UInt256()
        
        if shift == 0 {
            return lhs
        } else if shift < 64 {
            result.parts.3 = (lhs.parts.3 << shift) | (lhs.parts.2 >> (64 - shift))
            result.parts.2 = (lhs.parts.2 << shift) | (lhs.parts.1 >> (64 - shift))
            result.parts.1 = (lhs.parts.1 << shift) | (lhs.parts.0 >> (64 - shift))
            result.parts.0 = lhs.parts.0 << shift
        }
        
        return result
    }
    
    public static func >> (lhs: UInt256, rhs: UInt256) -> UInt256 {
        // Simplification: on suppose que le décalage est petit (< 64)
        guard rhs < UInt256(64) else { return UInt256() }
        let shift = Int(rhs.parts.0)
        
        var result = UInt256()
        
        if shift == 0 {
            return lhs
        } else if shift < 64 {
            result.parts.0 = (lhs.parts.0 >> shift) | (lhs.parts.1 << (64 - shift))
            result.parts.1 = (lhs.parts.1 >> shift) | (lhs.parts.2 << (64 - shift))
            result.parts.2 = (lhs.parts.2 >> shift) | (lhs.parts.3 << (64 - shift))
            result.parts.3 = lhs.parts.3 >> shift
        }
        
        return result
    }
    
    // MARK: - Initialisation privée
    
    private init(_ part0: UInt64, _ part1: UInt64, _ part2: UInt64, _ part3: UInt64) {
        self.parts = (part0, part1, part2, part3)
    }
}

// MARK: - Conformances utiles

extension UInt256: CustomStringConvertible {
    public var description: String {
        return "0x" + hexString
    }
}

extension UInt256: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(value)
    }
}

// MARK: - Fonctions utilitaires

public extension Data {
    /// Crée un UInt256 à partir des données (little-endian par défaut)
    func toUInt256() -> UInt256? {
        guard count >= 32 else { return nil }
        return UInt256(littleEndian: self)
    }
}

public extension String {
    /// Crée un UInt256 à partir d'une chaîne hexadécimale
    func hexToUInt256() -> UInt256? {
        // Supprimer le préfixe 0x si présent
        let hexString = hasPrefix("0x") ? String(dropFirst(2)) : self
        
        // Vérifier que la longueur est paire et ne dépasse pas 64 caractères (256 bits)
        guard hexString.count <= 64, hexString.count % 2 == 0 else { return nil }
        
        // Remplir avec des zéros à gauche si nécessaire
        let paddedHex = String(repeating: "0", count: 64 - hexString.count) + hexString
        
        // Convertir en données binaires
        var data = Data(capacity: 32)
        var index = paddedHex.startIndex
        
        for _ in 0..<32 {
            let byteString = String(paddedHex[index..<paddedHex.index(index, offsetBy: 2)])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = paddedHex.index(index, offsetBy: 2)
        }
        
        return UInt256(littleEndian: data)
    }
}
