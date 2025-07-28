import XCTest
import NIO
@testable import M1MinerCore

final class StratumClientTests: XCTestCase {
    
    var eventLoopGroup: EventLoopGroup!
    var stratumClient: StratumClient!
    let testConfig = StratumConfig(
        host: "example.com",
        port: 3032,
        username: "test.wallet",
        password: "x"
    )
    
    override func setUp() {
        super.setUp()
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        stratumClient = StratumClient(config: testConfig, eventLoopGroup: eventLoopGroup)
    }
    
    override func tearDown() {
        try? eventLoopGroup.syncShutdownGracefully()
        super.tearDown()
    }
    
    func testConnection() {
        let expectation = self.expectation(description: "Connection should complete")
        
        stratumClient.connect().whenComplete { result in
            switch result {
            case .success():
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Connection failed with error: \(error)")
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testSubscribe() {
        let connectExpectation = self.expectation(description: "Connection should complete"
        let subscribeExpectation = self.expectation(description: "Subscribe should complete")
        
        stratumClient.connect().whenComplete { result in
            switch result {
            case .success():
                connectExpectation.fulfill()
                
                self.stratumClient.subscribe().whenComplete { result in
                    switch result {
                    case .success():
                        subscribeExpectation.fulfill()
                    case .failure(let error):
                        XCTFail("Subscribe failed with error: \(error)")
                    }
                }
                
            case .failure(let error):
                XCTFail("Connection failed with error: \(error)")
            }
        }
        
        waitForExpectations(timeout: 15, handler: nil)
    }
    
    func testAuthorize() {
        let connectExpectation = self.expectation(description: "Connection should complete")
        let authExpectation = self.expectation(description: "Authorize should complete")
        
        stratumClient.connect().whenComplete { result in
            switch result {
            case .success():
                connectExpectation.fulfill()
                
                self.stratumClient.authorize().whenComplete { result in
                    switch result {
                    case .success(let isAuthorized):
                        XCTAssertTrue(isAuthorized, "Authorization should be successful")
                        authExpectation.fulfill()
                    case .failure(let error):
                        XCTFail("Authorization failed with error: \(error)")
                    }
                }
                
            case .failure(let error):
                XCTFail("Connection failed with error: \(error)")
            }
        }
        
        waitForExpectations(timeout: 15, handler: nil)
    }
    
    func testSubmitShare() {
        let connectExpectation = self.expectation(description: "Connection should complete")
        let submitExpectation = self.expectation(description: "Submit should complete")
        
        // Données de test pour la soumission
        let jobId = "test_job_id"
        let nonce = "12345678"
        let headerHash = "0000000000000000000000000000000000000000000000000000000000000000"
        let mixHash = "0000000000000000000000000000000000000000000000000000000000000000"
        
        stratumClient.connect().whenComplete { result in
            switch result {
            case .success():
                connectExpectation.fulfill()
                
                self.stratumClient.submitShare(
                    jobId: jobId,
                    nonce: nonce,
                    headerHash: headerHash,
                    mixHash: mixHash
                ).whenComplete { result in
                    switch result {
                    case .success():
                        submitExpectation.fulfill()
                    case .failure(let error):
                        XCTFail("Submit failed with error: \(error)")
                    }
                }
                
            case .failure(let error):
                XCTFail("Connection failed with error: \(error)")
            }
        }
        
        waitForExpectations(timeout: 15, handler: nil)
    }
    
    func testReconnection() {
        let firstConnection = self.expectation(description: "First connection should complete")
        let reconnectExpectation = self.expectation(description: "Reconnection should complete")
        
        // Première connexion
        stratumClient.connect().whenComplete { result in
            switch result {
            case .success():
                firstConnection.fulfill()
                
                // Simuler une déconnexion
                self.stratumClient.disconnect()
                
                // Tenter de se reconnecter
                self.stratumClient.connect().whenComplete { result in
                    switch result {
                    case .success():
                        reconnectExpectation.fulfill()
                    case .failure(let error):
                        XCTFail("Reconnection failed with error: \(error)")
                    }
                }
                
            case .failure(let error):
                XCTFail("First connection failed with error: \(error)")
            }
        }
        
        waitForExpectations(timeout: 30, handler: nil)
    }
}
