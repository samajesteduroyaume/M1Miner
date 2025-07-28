import XCTest
@testable import M1MinerCore

final class InputValidatorTests: XCTestCase {
    
    // MARK: - Test validateWorkerName
    
    func testValidateWorkerName_ValidName_ReturnsTrimmedName() {
        // Given
        let name = " worker1 "
        
        // When
        let result = try? InputValidator.validateWorkerName(name)
        
        // Then
        XCTAssertEqual(result, "worker1")
    }
    
    func testValidateWorkerName_EmptyName_ThrowsError() {
        // Given
        let name = ""
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validateWorkerName(name)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .emptyWorkerName = validationError {
                // Success
            } else {
                XCTFail("Expected emptyWorkerName error")
            }
        }
    }
    
    func testValidateWorkerName_TooLongName_ThrowsError() {
        // Given
        let name = String(repeating: "a", count: InputValidator.maxWorkerNameLength + 1)
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validateWorkerName(name)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .workerNameTooLong = validationError {
                // Success
            } else {
                XCTFail("Expected workerNameTooLong error")
            }
        }
    }
    
    func testValidateWorkerName_InvalidCharacters_ThrowsError() {
        // Given
        let names = ["worker@1", "worker#1", "worker 1", "worker\"1"]
        
        // When/Then
        for name in names {
            XCTAssertThrowsError(try InputValidator.validateWorkerName(name)) { error in
                guard let validationError = error as? InputValidator.ValidationError else {
                    return XCTFail("Expected ValidationError for '\(name)'")
                }
                
                if case .invalidWorkerNameCharacters = validationError {
                    // Success
                } else {
                    XCTFail("Expected invalidWorkerNameCharacters error for '\(name)'")
                }
            }
        }
    }
    
    // MARK: - Test validatePassword
    
    func testValidatePassword_ValidPassword_ReturnsTrimmedPassword() {
        // Given
        let password = " pass123 "
        
        // When
        let result = try? InputValidator.validatePassword(password)
        
        // Then
        XCTAssertEqual(result, "pass123")
    }
    
    func testValidatePassword_TooLongPassword_ThrowsError() {
        // Given
        let password = String(repeating: "a", count: InputValidator.maxPasswordLength + 1)
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validatePassword(password)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .passwordTooLong = validationError {
                // Success
            } else {
                XCTFail("Expected passwordTooLong error")
            }
        }
    }
    
    // MARK: - Test validateJobId
    
    func testValidateJobId_ValidJobId_ReturnsTrimmedJobId() {
        // Given
        let jobId = " 123abc "
        
        // When
        let result = try? InputValidator.validateJobId(jobId)
        
        // Then
        XCTAssertEqual(result, "123abc")
    }
    
    func testValidateJobId_EmptyJobId_ThrowsError() {
        // Given
        let jobId = ""
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validateJobId(jobId)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .emptyJobId = validationError {
                // Success
            } else {
                XCTFail("Expected emptyJobId error")
            }
        }
    }
    
    // MARK: - Test validateExtraNonce
    
    func testValidateExtraNonce_ValidNonce_ReturnsNonce() {
        // Given
        let nonce = " 123abc "
        
        // When
        let result = try? InputValidator.validateExtraNonce(nonce)
        
        // Then
        XCTAssertEqual(result, "123abc")
    }
    
    func testValidateExtraNonce_InvalidHex_ThrowsError() {
        // Given
        let nonce = "123xyz"
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validateExtraNonce(nonce)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .invalidHexString = validationError {
                // Success
            } else {
                XCTFail("Expected invalidHexString error")
            }
        }
    }
    
    // MARK: - Test validateNTime
    
    func testValidateNTime_ValidNTime_ReturnsNTime() {
        // Given
        let ntime = "12345678"
        
        // When
        let result = try? InputValidator.validateNTime(ntime)
        
        // Then
        XCTAssertEqual(result, ntime)
    }
    
    func testValidateNTime_InvalidLength_ThrowsError() {
        // Given
        let ntime = "1234567" // Should be 8 characters
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validateNTime(ntime)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .invalidNTimeLength = validationError {
                // Success
            } else {
                XCTFail("Expected invalidNTimeLength error")
            }
        }
    }
    
    // MARK: - Test validateNonce
    
    func testValidateNonce_ValidNonce_ReturnsNonce() {
        // Given
        let nonce = "12345678"
        
        // When
        let result = try? InputValidator.validateNonce(nonce)
        
        // Then
        XCTAssertEqual(result, nonce)
    }
    
    func testValidateNonce_InvalidLength_ThrowsError() {
        // Given
        let nonce = "1234567" // Should be 8 characters
        
        // When/Then
        XCTAssertThrowsError(try InputValidator.validateNonce(nonce)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                return XCTFail("Expected ValidationError")
            }
            
            if case .invalidNonceLength = validationError {
                // Success
            } else {
                XCTFail("Expected invalidNonceLength error")
            }
        }
    }
}
