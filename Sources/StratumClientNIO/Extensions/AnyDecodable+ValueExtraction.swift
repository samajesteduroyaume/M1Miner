import Foundation

extension AnyDecodable {
    /// Safely extracts a value of the specified type
    /// - Parameter type: The expected type to extract
    /// - Returns: The extracted value if successful
    /// - Throws: `DecodingError.typeMismatch` if the value cannot be cast to the expected type
    public func extract<T>(as type: T.Type = T.self) throws -> T {
        guard let value = value as? T else {
            throw DecodingError.typeMismatch(
                T.self,
                .init(codingPath: [],
                      debugDescription: "Expected to decode \(T.self) but found \(Swift.type(of: value)) instead.")
            )
        }
        return value
    }
    
    /// Safely extracts a dictionary with String keys and any value
    /// - Returns: The extracted dictionary if successful
    /// - Throws: `DecodingError.typeMismatch` if the value is not a dictionary
    public func extractDictionary() throws -> [String: Any] {
        try extract(as: [String: Any].self)
    }
    
    /// Safely extracts an array of any values
    /// - Returns: The extracted array if successful
    /// - Throws: `DecodingError.typeMismatch` if the value is not an array
    public func extractArray() throws -> [Any] {
        try extract(as: [Any].self)
    }
    
    /// Safely extracts a string value
    /// - Returns: The extracted string if successful
    /// - Throws: `DecodingError.typeMismatch` if the value is not a string
    public func extractString() throws -> String {
        try extract(as: String.self)
    }
    
    /// Safely extracts a boolean value
    /// - Returns: The extracted boolean if successful
    /// - Throws: `DecodingError.typeMismatch` if the value is not a boolean
    public func extractBool() throws -> Bool {
        try extract(as: Bool.self)
    }
    
    /// Safely extracts an integer value
    /// - Returns: The extracted integer if successful
    /// - Throws: `DecodingError.typeMismatch` if the value is not an integer
    public func extractInt() throws -> Int {
        try extract(as: Int.self)
    }
    
    /// Safely extracts a double value
    /// - Returns: The extracted double if successful
    /// - Throws: `DecodingError.typeMismatch` if the value is not a double
    public func extractDouble() throws -> Double {
        try extract(as: Double.self)
    }
    
    /// Safely extracts a value of the specified type if possible
    /// - Parameter type: The expected type to extract
    /// - Returns: The extracted value if successful, nil otherwise
    public func extractIfPresent<T>(as type: T.Type = T.self) -> T? {
        try? extract(as: type)
    }
    
    /// Safely extracts a dictionary if possible
    /// - Returns: The extracted dictionary if successful, nil otherwise
    public func extractDictionaryIfPresent() -> [String: Any]? {
        extractIfPresent(as: [String: Any].self)
    }
    
    /// Safely extracts an array if possible
    /// - Returns: The extracted array if successful, nil otherwise
    public func extractArrayIfPresent() -> [Any]? {
        extractIfPresent(as: [Any].self)
    }
    
    /// Safely extracts a string if possible
    /// - Returns: The extracted string if successful, nil otherwise
    public func extractStringIfPresent() -> String? {
        extractIfPresent(as: String.self)
    }
    
    /// Safely extracts a boolean if possible
    /// - Returns: The extracted boolean if successful, nil otherwise
    public func extractBoolIfPresent() -> Bool? {
        extractIfPresent(as: Bool.self)
    }
    
    /// Safely extracts an integer if possible
    /// - Returns: The extracted integer if successful, nil otherwise
    public func extractIntIfPresent() -> Int? {
        extractIfPresent(as: Int.self)
    }
    
    /// Safely extracts a double if possible
    /// - Returns: The extracted double if successful, nil otherwise
    public func extractDoubleIfPresent() -> Double? {
        extractIfPresent(as: Double.self)
    }
}
