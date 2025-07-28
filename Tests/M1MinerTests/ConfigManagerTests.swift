import XCTest
@testable import M1MinerCore

final class ConfigManagerTests: XCTestCase {
    
    var configManager: ConfigManager!
    let testConfigPath = "/tmp/test_config.json"
    
    override func setUp() {
        super.setUp()
        configManager = ConfigManager()
        
        // Créer un fichier de test
        let testConfig = """
        {
            "poolUrl": "stratum+tcp://example.com:3032",
            "username": "test.wallet",
            "password": "x",
            "algorithm": "kawpow",
            "deviceId": 0,
            "intensity": 19
        }
        """
        
        try? testConfig.write(toFile: testConfigPath, atomically: true, encoding: .utf8)
    }
    
    override func tearDown() {
        // Nettoyer le fichier de test
        try? FileManager.default.removeItem(atPath: testConfigPath)
        super.tearDown()
    }
    
    func testLoadConfig() {
        // When
        let config = try? configManager.loadConfig(from: testConfigPath)
        
        // Then
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.poolUrl, "stratum+tcp://example.com:3032")
        XCTAssertEqual(config?.username, "test.wallet")
        XCTAssertEqual(config?.algorithm, "kawpow")
    }
    
    func testMissingRequiredField() {
        // Given
        let invalidConfig = """
        {
            "poolUrl": "stratum+tcp://example.com:3032",
            "username": "test.wallet"
            // Missing required fields
        }
        """
        try? invalidConfig.write(toFile: testConfigPath, atomically: true, encoding: .utf8)
        
        // When/Then
        XCTAssertThrowsError(try configManager.loadConfig(from: testConfigPath)) { error in
            XCTAssertTrue(error is ConfigError)
        }
    }
    
    func testInvalidJSON() {
        // Given
        let invalidJSON = "{ invalid json }"
        try? invalidJSON.write(toFile: testConfigPath, atomically: true, encoding: .utf8)
        
        // When/Then
        XCTAssertThrowsError(try configManager.loadConfig(from: testConfigPath))
    }
}

// Extension pour rendre les tests plus lisibles
extension ConfigManager {
    func loadConfig(from path: String) throws -> MinerConfig {
        let url = URL(fileURLWithPath: path)
        return try loadConfig(from: url)
    }
}
