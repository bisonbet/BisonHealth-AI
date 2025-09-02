import XCTest
@testable import HealthApp

final class ValidationHelperTests: XCTestCase {
    
    // MARK: - Name Validation Tests
    
    func testValidNames() {
        let validNames = [
            "John Doe",
            "Mary Jane Smith",
            "O'Connor",
            "Jean-Luc",
            "Dr. Smith",
            "José María",
            "李小明", // Chinese characters
            "محمد", // Arabic characters
        ]
        
        for name in validNames {
            let result = ValidationHelper.validateName(name)
            XCTAssertTrue(result.isValid, "Name '\(name)' should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidNames() {
        let invalidCases: [(name: String, expectedError: String)] = [
            ("A", "at least 2 characters"),
            (String(repeating: "A", count: 101), "less than 100 characters"),
            ("John123", "can only contain letters"),
            ("John@Doe", "can only contain letters"),
            ("John#Doe", "can only contain letters"),
        ]
        
        for testCase in invalidCases {
            let result = ValidationHelper.validateName(testCase.name)
            XCTAssertFalse(result.isValid, "Name '\(testCase.name)' should be invalid")
            XCTAssertNotNil(result.errorMessage)
            XCTAssertTrue(result.errorMessage!.contains(testCase.expectedError))
        }
    }
    
    func testEmptyNameIsValid() {
        let result = ValidationHelper.validateName("")
        XCTAssertTrue(result.isValid, "Empty name should be valid (optional field)")
        XCTAssertNil(result.errorMessage)
        
        let whitespaceResult = ValidationHelper.validateName("   ")
        XCTAssertTrue(whitespaceResult.isValid, "Whitespace-only name should be valid (optional field)")
    }
    
    // MARK: - Date of Birth Validation Tests
    
    func testValidDateOfBirth() {
        let calendar = Calendar.current
        let now = Date()
        
        let validDates = [
            calendar.date(byAdding: .year, value: -25, to: now)!, // 25 years ago
            calendar.date(byAdding: .year, value: -1, to: now)!, // 1 year ago
            calendar.date(byAdding: .year, value: -100, to: now)!, // 100 years ago
            calendar.date(byAdding: .day, value: -1, to: now)!, // Yesterday
        ]
        
        for date in validDates {
            let result = ValidationHelper.validateDateOfBirth(date)
            XCTAssertTrue(result.isValid, "Date \(date) should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidDateOfBirth() {
        let calendar = Calendar.current
        let now = Date()
        
        // Future date
        let futureDate = calendar.date(byAdding: .day, value: 1, to: now)!
        let futureResult = ValidationHelper.validateDateOfBirth(futureDate)
        XCTAssertFalse(futureResult.isValid)
        XCTAssertTrue(futureResult.errorMessage!.contains("cannot be in the future"))
        
        // Too old (over 150 years)
        let tooOldDate = calendar.date(byAdding: .year, value: -151, to: now)!
        let tooOldResult = ValidationHelper.validateDateOfBirth(tooOldDate)
        XCTAssertFalse(tooOldResult.isValid)
        XCTAssertTrue(tooOldResult.errorMessage!.contains("valid date of birth"))
    }
    
    // MARK: - Height Validation Tests
    
    func testValidHeightInCentimeters() {
        let validHeights = [100.0, 150.0, 180.0, 220.0]
        
        for height in validHeights {
            let result = ValidationHelper.validateHeight(centimeters: height)
            XCTAssertTrue(result.isValid, "Height \(height) cm should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidHeightInCentimeters() {
        let tooShort = ValidationHelper.validateHeight(centimeters: 99.0)
        XCTAssertFalse(tooShort.isValid)
        XCTAssertTrue(tooShort.errorMessage!.contains("at least 100 cm"))
        
        let tooTall = ValidationHelper.validateHeight(centimeters: 221.0)
        XCTAssertFalse(tooTall.isValid)
        XCTAssertTrue(tooTall.errorMessage!.contains("less than 220 cm"))
    }
    
    func testValidHeightInFeetAndInches() {
        let validHeights = [(3, 0), (5, 8), (6, 2), (8, 11)]
        
        for (feet, inches) in validHeights {
            let result = ValidationHelper.validateHeight(feet: feet, inches: inches)
            XCTAssertTrue(result.isValid, "Height \(feet)'\(inches)\" should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidHeightInFeetAndInches() {
        let tooShort = ValidationHelper.validateHeight(feet: 2, inches: 11)
        XCTAssertFalse(tooShort.isValid)
        XCTAssertTrue(tooShort.errorMessage!.contains("at least 3 feet"))
        
        let tooTall = ValidationHelper.validateHeight(feet: 9, inches: 0)
        XCTAssertFalse(tooTall.isValid)
        XCTAssertTrue(tooTall.errorMessage!.contains("less than 9 feet"))
    }
    
    // MARK: - Weight Validation Tests
    
    func testValidWeightInKilograms() {
        let validWeights = [35.0, 70.0, 100.0, 180.0]
        
        for weight in validWeights {
            let result = ValidationHelper.validateWeight(kilograms: weight)
            XCTAssertTrue(result.isValid, "Weight \(weight) kg should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidWeightInKilograms() {
        let tooLight = ValidationHelper.validateWeight(kilograms: 34.0)
        XCTAssertFalse(tooLight.isValid)
        XCTAssertTrue(tooLight.errorMessage!.contains("at least 35 kg"))
        
        let tooHeavy = ValidationHelper.validateWeight(kilograms: 181.0)
        XCTAssertFalse(tooHeavy.isValid)
        XCTAssertTrue(tooHeavy.errorMessage!.contains("less than 180 kg"))
    }
    
    func testValidWeightInPounds() {
        let validWeights = [80.0, 150.0, 250.0, 400.0]
        
        for weight in validWeights {
            let result = ValidationHelper.validateWeight(pounds: weight)
            XCTAssertTrue(result.isValid, "Weight \(weight) lbs should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidWeightInPounds() {
        let tooLight = ValidationHelper.validateWeight(pounds: 79.0)
        XCTAssertFalse(tooLight.isValid)
        XCTAssertTrue(tooLight.errorMessage!.contains("at least 80 lbs"))
        
        let tooHeavy = ValidationHelper.validateWeight(pounds: 401.0)
        XCTAssertFalse(tooHeavy.isValid)
        XCTAssertTrue(tooHeavy.errorMessage!.contains("less than 400 lbs"))
    }
    
    // MARK: - Blood Test Validation Tests
    
    func testValidTestDate() {
        let calendar = Calendar.current
        let now = Date()
        
        let validDates = [
            now, // Today
            calendar.date(byAdding: .day, value: -1, to: now)!, // Yesterday
            calendar.date(byAdding: .year, value: -1, to: now)!, // 1 year ago
            calendar.date(byAdding: .year, value: -5, to: now)!, // 5 years ago
        ]
        
        for date in validDates {
            let result = ValidationHelper.validateTestDate(date)
            XCTAssertTrue(result.isValid, "Test date \(date) should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidTestDate() {
        let calendar = Calendar.current
        let now = Date()
        
        // Future date
        let futureDate = calendar.date(byAdding: .day, value: 1, to: now)!
        let futureResult = ValidationHelper.validateTestDate(futureDate)
        XCTAssertFalse(futureResult.isValid)
        XCTAssertTrue(futureResult.errorMessage!.contains("cannot be in the future"))
        
        // Too old (over 10 years)
        let tooOldDate = calendar.date(byAdding: .year, value: -11, to: now)!
        let tooOldResult = ValidationHelper.validateTestDate(tooOldDate)
        XCTAssertFalse(tooOldResult.isValid)
        XCTAssertTrue(tooOldResult.errorMessage!.contains("too old"))
    }
    
    func testValidTestName() {
        let validNames = [
            "Glucose",
            "Total Cholesterol",
            "HDL-C",
            "LDL Cholesterol",
            "Hemoglobin A1c",
            "WBC",
        ]
        
        for name in validNames {
            let result = ValidationHelper.validateTestName(name)
            XCTAssertTrue(result.isValid, "Test name '\(name)' should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidTestName() {
        let emptyResult = ValidationHelper.validateTestName("")
        XCTAssertFalse(emptyResult.isValid)
        XCTAssertTrue(emptyResult.errorMessage!.contains("required"))
        
        let tooLongName = String(repeating: "A", count: 51)
        let tooLongResult = ValidationHelper.validateTestName(tooLongName)
        XCTAssertFalse(tooLongResult.isValid)
        XCTAssertTrue(tooLongResult.errorMessage!.contains("less than 50 characters"))
    }
    
    func testValidTestValue() {
        let validValues = [
            "95",
            "180.5",
            "< 5",
            "> 300",
            "Normal",
            "Negative",
        ]
        
        for value in validValues {
            let result = ValidationHelper.validateTestValue(value)
            XCTAssertTrue(result.isValid, "Test value '\(value)' should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidTestValue() {
        let emptyResult = ValidationHelper.validateTestValue("")
        XCTAssertFalse(emptyResult.isValid)
        XCTAssertTrue(emptyResult.errorMessage!.contains("required"))
        
        let tooLongValue = String(repeating: "A", count: 21)
        let tooLongResult = ValidationHelper.validateTestValue(tooLongValue)
        XCTAssertFalse(tooLongResult.isValid)
        XCTAssertTrue(tooLongResult.errorMessage!.contains("less than 20 characters"))
    }
    
    func testValidBloodTestResults() {
        let validResults = [
            BloodTestItem(name: "Glucose", value: "95"),
            BloodTestItem(name: "Cholesterol", value: "180"),
            BloodTestItem(name: "HDL", value: "45"),
        ]
        
        let result = ValidationHelper.validateBloodTestResults(validResults)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }
    
    func testInvalidBloodTestResults() {
        // Empty results
        let emptyResult = ValidationHelper.validateBloodTestResults([])
        XCTAssertFalse(emptyResult.isValid)
        XCTAssertTrue(emptyResult.errorMessage!.contains("at least one"))
        
        // Duplicate names
        let duplicateResults = [
            BloodTestItem(name: "Glucose", value: "95"),
            BloodTestItem(name: "glucose", value: "100"), // Case insensitive duplicate
        ]
        let duplicateResult = ValidationHelper.validateBloodTestResults(duplicateResults)
        XCTAssertFalse(duplicateResult.isValid)
        XCTAssertTrue(duplicateResult.errorMessage!.contains("Duplicate"))
        
        // Invalid individual result
        let invalidResults = [
            BloodTestItem(name: "", value: "95"), // Empty name
        ]
        let invalidResult = ValidationHelper.validateBloodTestResults(invalidResults)
        XCTAssertFalse(invalidResult.isValid)
        XCTAssertTrue(invalidResult.errorMessage!.contains("required"))
    }
    
    // MARK: - Email Validation Tests
    
    func testValidEmails() {
        let validEmails = [
            "",
            "   ", // Empty/whitespace should be valid (optional)
            "test@example.com",
            "user.name@domain.co.uk",
            "user+tag@example.org",
            "123@example.com",
        ]
        
        for email in validEmails {
            let result = ValidationHelper.validateEmail(email)
            XCTAssertTrue(result.isValid, "Email '\(email)' should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidEmails() {
        let invalidEmails = [
            "invalid",
            "@example.com",
            "test@",
            "test.example.com",
            "test@.com",
            "test@example.",
        ]
        
        for email in invalidEmails {
            let result = ValidationHelper.validateEmail(email)
            XCTAssertFalse(result.isValid, "Email '\(email)' should be invalid")
            XCTAssertTrue(result.errorMessage!.contains("valid email"))
        }
    }
    
    // MARK: - Phone Number Validation Tests
    
    func testValidPhoneNumbers() {
        let validPhones = [
            "",
            "   ", // Empty/whitespace should be valid (optional)
            "1234567890",
            "(555) 123-4567",
            "+1 555 123 4567",
            "555.123.4567",
            "+44 20 7946 0958", // UK number
        ]
        
        for phone in validPhones {
            let result = ValidationHelper.validatePhoneNumber(phone)
            XCTAssertTrue(result.isValid, "Phone '\(phone)' should be valid")
            XCTAssertNil(result.errorMessage)
        }
    }
    
    func testInvalidPhoneNumbers() {
        let tooShort = ValidationHelper.validatePhoneNumber("123456789") // 9 digits
        XCTAssertFalse(tooShort.isValid)
        XCTAssertTrue(tooShort.errorMessage!.contains("at least 10 digits"))
        
        let tooLong = ValidationHelper.validatePhoneNumber("1234567890123456") // 16 digits
        XCTAssertFalse(tooLong.isValid)
        XCTAssertTrue(tooLong.errorMessage!.contains("less than 15 digits"))
    }
    
    // MARK: - Edge Cases and Performance Tests
    
    func testValidationPerformance() {
        let longName = String(repeating: "A", count: 50)
        
        measure {
            for _ in 0..<1000 {
                _ = ValidationHelper.validateName(longName)
            }
        }
    }
    
    func testUnicodeHandling() {
        let unicodeNames = [
            "José María García",
            "李小明",
            "محمد عبدالله",
            "Владимир Путин",
            "Αλέξανδρος",
        ]
        
        for name in unicodeNames {
            let result = ValidationHelper.validateName(name)
            XCTAssertTrue(result.isValid, "Unicode name '\(name)' should be valid")
        }
    }
    
    func testValidationResultEquality() {
        let valid1 = ValidationHelper.ValidationResult.valid
        let valid2 = ValidationHelper.ValidationResult.valid
        
        XCTAssertEqual(valid1.isValid, valid2.isValid)
        XCTAssertEqual(valid1.errorMessage, valid2.errorMessage)
        
        let invalid1 = ValidationHelper.ValidationResult.invalid("Test error")
        let invalid2 = ValidationHelper.ValidationResult.invalid("Test error")
        
        XCTAssertEqual(invalid1.isValid, invalid2.isValid)
        XCTAssertEqual(invalid1.errorMessage, invalid2.errorMessage)
    }
}