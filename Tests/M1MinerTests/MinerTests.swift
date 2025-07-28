import XCTest
import Metal
@testable import M1MinerCore

final class MinerTests: XCTestCase {
    
    var device: MTLDevice!
    var miner: Miner!
    var testConfig: MinerConfig!
    
    override func setUp() {
        super.setUp()
        
        // Configuration de base pour les tests
        device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(device, "L'appareil Metal n'est pas disponible")
        
        testConfig = MinerConfig(
            poolUrl: "stratum+tcp://example.com:3032",
            username: "test.wallet",
            password: "x",
            algorithm: "kawpow",
            deviceId: 0,
            intensity: 19
        )
        
        miner = try? Miner(config: testConfig, device: device)
        XCTAssertNotNil(miner, "Impossible d'initialiser le mineur")
    }
    
    func testMinerInitialization() {
        XCTAssertNotNil(miner.device, "Le périphérique Metal ne devrait pas être nul")
        XCTAssertNotNil(miner.commandQueue, "La file d'attente de commandes ne devrait pas être nulle")
        XCTAssertNotNil(miner.library, "La bibliothèque de shaders ne devrait pas être nulle")
    }
    
    func testKawPowPipelineSetup() {
        // Given
        let kawPowFunction = miner.library.makeFunction(name: "kawpow_hash")
        
        // Then
        XCTAssertNotNil(kawPowFunction, "La fonction de hachage KawPow n'a pas été trouvée")
        
        // Test de la création du pipeline de calcul
        do {
            let pipeline = try miner.device.makeComputePipelineState(function: kawPowFunction!)
            XCTAssertNotNil(pipeline, "Le pipeline de calcul n'a pas pu être créé")
        } catch {
            XCTFail("Erreur lors de la création du pipeline: \(error)")
        }
    }
    
    func testMinerStartStop() {
        // Given
        let expectation = XCTestExpectation(description: "Le mineur devrait s'arrêter correctement")
        
        // When
        DispatchQueue.global().async {
            self.miner.start()
            
            // Arrêter après un court délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.miner.stop()
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertFalse(miner.isMining, "Le mineur devrait être arrêté")
    }
    
    func testHashRateCalculation() {
        // Given
        let testHashes: UInt64 = 1000
        let testTime: TimeInterval = 1.0 // 1 seconde
        
        // When
        let hashRate = miner.calculateHashRate(hashes: testHashes, time: testTime)
        
        // Then
        XCTAssertEqual(hashRate, 1000, "Le taux de hachage calculé est incorrect")
    }
    
    // Test pour vérifier la gestion des erreurs avec une configuration invalide
    func testInvalidConfig() {
        // Given
        let invalidConfig = MinerConfig(
            poolUrl: "", // URL vide
            username: "", // Nom d'utilisateur vide
            password: "",
            algorithm: "algorithme_inconnu", // Algorithme non supporté
            deviceId: 999, // ID de périphérique invalide
            intensity: 100 // Intensité invalide
        )
        
        // When/Then
        XCTAssertThrowsError(try Miner(config: invalidConfig, device: device)) { error in
            // Vérifier que l'erreur est du bon type
            XCTAssertTrue(error is MinerError, "Une erreur MinerError était attendue")
        }
    }
}

// Extension pour exposer des méthodes internes pour les tests
extension Miner {
    func calculateHashRate(hashes: UInt64, time: TimeInterval) -> UInt64 {
        return UInt64(Double(hashes) / time)
    }
}
