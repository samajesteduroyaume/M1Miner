import XCTest
@testable import M1MinerCore

final class ReplayProtectionTests: XCTestCase {
    
    var replayProtection: ReplayProtection!
    
    override func setUp() {
        super.setUp()
        replayProtection = ReplayProtection()
    }
    
    override func tearDown() {
        replayProtection = nil
        super.tearDown()
    }
    
    func testIsNonceValid_NewNonce_ReturnsTrue() {
        // Given
        let nonce = "abcdef12"
        let jobId = "job123"
        
        // When
        let isValid = replayProtection.isNonceValid(nonce, forJobId: jobId)
        
        // Then
        XCTAssertTrue(isValid)
    }
    
    func testIsNonceValid_UsedNonce_ReturnsFalse() {
        // Given
        let nonce = "abcdef12"
        let jobId = "job123"
        
        // When
        replayProtection.markNonceAsUsed(nonce, forJobId: jobId)
        let isValid = replayProtection.isNonceValid(nonce, forJobId: jobId)
        
        // Then
        XCTAssertFalse(isValid)
    }
    
    func testIsNonceValid_DifferentJobIds_DontCollide() {
        // Given
        let nonce = "abcdef12"
        let jobId1 = "job123"
        let jobId2 = "job456"
        
        // When
        replayProtection.markNonceAsUsed(nonce, forJobId: jobId1)
        let isValidForJob2 = replayProtection.isNonceValid(nonce, forJobId: jobId2)
        
        // Then
        XCTAssertTrue(isValidForJob2)
    }
    
    func testClear_RemovesAllNonces() {
        // Given
        let nonce1 = "abcdef12"
        let nonce2 = "34567890"
        let jobId = "job123"
        
        // When
        replayProtection.markNonceAsUsed(nonce1, forJobId: jobId)
        replayProtection.markNonceAsUsed(nonce2, forJobId: jobId)
        replayProtection.clear()
        
        // Then
        XCTAssertTrue(replayProtection.isNonceValid(nonce1, forJobId: jobId))
        XCTAssertTrue(replayProtection.isNonceValid(nonce2, forJobId: jobId))
    }
    
    func testUseNonceIfValid_FirstTime_ReturnsTrue() {
        // Given
        let nonce = "abcdef12"
        let jobId = "job123"
        
        // When
        let result = replayProtection.useNonceIfValid(nonce, forJobId: jobId)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertFalse(replayProtection.isNonceValid(nonce, forJobId: jobId))
    }
    
    func testUseNonceIfValid_SecondTime_ReturnsFalse() {
        // Given
        let nonce = "abcdef12"
        let jobId = "job123"
        
        // When
        _ = replayProtection.useNonceIfValid(nonce, forJobId: jobId)
        let result = replayProtection.useNonceIfValid(nonce, forJobId: jobId)
        
        // Then
        XCTAssertFalse(result)
    }
    
    func testWindowSize_RespectsMaximumSize() {
        // Given
        let windowSize = 10
        replayProtection = ReplayProtection(windowSize: windowSize)
        let jobId = "job123"
        
        // When - Add more nonces than the window size
        for i in 0..<(windowSize * 2) {
            let nonce = String(format: "%08x", i)
            replayProtection.markNonceAsUsed(nonce, forJobId: jobId)
        }
        
        // Then - Only the most recent nonces should be kept
        for i in 0..<windowSize {
            let nonce = String(format: "%08x", i)
            XCTAssertTrue(replayProtection.isNonceValid(nonce, forJobId: jobId), 
                        "Nonce \(nonce) should have been evicted from the window")
        }
        
        for i in windowSize..<(windowSize * 2) {
            let nonce = String(format: "%08x", i)
            XCTAssertFalse(replayProtection.isNonceValid(nonce, forJobId: jobId), 
                         "Nonce \(nonce) should still be in the window")
        }
    }
    
    func testValidateAndRegisterSubmission_ValidSubmission_ReturnsTrue() {
        // Given
        let jobId = "job123"
        let extranonce2 = "12345678"
        let ntime = "5a0e1b2c"
        let nonce = "deadbeef"
        
        // When
        let result = replayProtection.validateAndRegisterSubmission(
            jobId: jobId,
            extranonce2: extranonce2,
            ntime: ntime,
            nonce: nonce
        )
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testValidateAndRegisterSubmission_DuplicateSubmission_ReturnsFalse() {
        // Given
        let jobId = "job123"
        let extranonce2 = "12345678"
        let ntime = "5a0e1b2c"
        let nonce = "deadbeef"
        
        // When
        _ = replayProtection.validateAndRegisterSubmission(
            jobId: jobId,
            extranonce2: extranonce2,
            ntime: ntime,
            nonce: nonce
        )
        
        let result = replayProtection.validateAndRegisterSubmission(
            jobId: jobId,
            extranonce2: extranonce2,
            ntime: ntime,
            nonce: nonce
        )
        
        // Then
        XCTAssertFalse(result)
    }
}
