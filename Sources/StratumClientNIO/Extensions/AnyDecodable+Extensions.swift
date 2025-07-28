import Foundation
import M1MinerShared

// MARK: - Extensions pour la conversion de types vers AnyDecodable

extension String {
    public var asAnyDecodable: AnyDecodable { AnyDecodable(self) }
}

extension Int {
    public var asAnyDecodable: AnyDecodable { AnyDecodable(self) }
}

extension Double {
    public var asAnyDecodable: AnyDecodable { AnyDecodable(self) }
}

extension Bool {
    public var asAnyDecodable: AnyDecodable { AnyDecodable(self) }
}

extension Array where Element == Any {
    public var asAnyDecodable: AnyDecodable { 
        AnyDecodable(self.map { AnyDecodable($0) }) 
    }
}

extension Dictionary where Key == String, Value == Any {
    public var asAnyDecodable: AnyDecodable {
        AnyDecodable(self.mapValues { AnyDecodable($0) })
    }
}

// Fonction utilitaire pour convertir n'importe quelle valeur en AnyDecodable
public func toAnyDecodable(_ value: Any) -> AnyDecodable {
    switch value {
    case let string as String:
        return string.asAnyDecodable
    case let int as Int:
        return int.asAnyDecodable
    case let double as Double:
        return double.asAnyDecodable
    case let bool as Bool:
        return bool.asAnyDecodable
    case let array as [Any]:
        return array.asAnyDecodable
    case let dict as [String: Any]:
        return dict.asAnyDecodable
    default:
        return AnyDecodable("\(value)")
    }
}

// MARK: - Extensions pour la lecture des valeurs

extension AnyDecodable {
    /// Tente d'obtenir une valeur de type String
    /// - Throws: Une erreur si la conversion échoue
    /// - Returns: La valeur sous forme de String
    func stringValue() throws -> String {
        guard let value = value as? String else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: [], debugDescription: "Expected String but found \(type(of: value))")
            )
        }
        return value
    }
    
    /// Tente d'obtenir une valeur de type Bool
    /// - Throws: Une erreur si la conversion échoue
    /// - Returns: La valeur sous forme de Bool
    func boolValue() throws -> Bool {
        guard let value = value as? Bool else {
            throw DecodingError.typeMismatch(
                Bool.self,
                .init(codingPath: [], debugDescription: "Expected Bool but found \(type(of: value))")
            )
        }
        return value
    }
    
    /// Tente d'obtenir une valeur de type Double
    /// - Throws: Une erreur si la conversion échoue
    /// - Returns: La valeur sous forme de Double
    func doubleValue() throws -> Double {
        if let value = value as? Double {
            return value
        } else if let value = value as? Int {
            return Double(value)
        } else if let value = value as? String, let doubleValue = Double(value) {
            return doubleValue
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                .init(codingPath: [], debugDescription: "Expected Double but found \(type(of: value))")
            )
        }
    }
    
    /// Tente d'obtenir un tableau de AnyDecodable
    /// - Throws: Une erreur si la conversion échoue
    /// - Returns: Un tableau de AnyDecodable
    func arrayValue() throws -> [AnyDecodable] {
        guard let array = value as? [Any] else {
            throw DecodingError.typeMismatch(
                [Any].self,
                .init(codingPath: [], debugDescription: "Expected Array but found \(type(of: value))")
            )
        }
        
        return array.map { item in
            if let decodable = item as? AnyDecodable {
                return decodable
            } else {
                // Créer un AnyDecodable à partir de la valeur
                do {
                    let decoder = JSONDecoder()
                    let data = try JSONSerialization.data(withJSONObject: ["value": item])
                    let wrapper = try decoder.decode(Wrapper.self, from: data)
                    return wrapper.value
                } catch {
                    // En cas d'erreur, retourner une valeur par défaut
                    // Créer un AnyDecodable en utilisant la valeur directement
                    let mirror = Mirror(reflecting: item)
                    switch item {
                    case let string as String:
                        return AnyDecodable(string)
                    case let int as Int:
                        return AnyDecodable(int)
                    case let double as Double:
                        return AnyDecodable(double)
                    case let bool as Bool:
                        return AnyDecodable(bool)
                    case let array as [Any]:
                        return AnyDecodable(array.map { AnyDecodable($0) })
                    case let dict as [String: Any]:
                        return AnyDecodable(dict.mapValues { AnyDecodable($0) })
                    default:
                        // Si le type n'est pas reconnu, retourner une chaîne vide
                        return AnyDecodable("")
                    }
                }
            }
        }
    }
    
    /// Wrapper pour décoder des valeurs simples dans un conteneur
    private struct Wrapper: Decodable {
        let value: AnyDecodable
    }
}
