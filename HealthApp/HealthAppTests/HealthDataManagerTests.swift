import XCTest
@testable import HealthApp

@MainActor
final class HealthDataManagerTests: XCTestCase {

    func testValidationResultStoresCurrentState() {
        let valid = ValidationResult(isValid: true, errors: [])
        XCTAssertTrue(valid.isValid)
        XCTAssertTrue(valid.errors.isEmpty)

        let invalid = ValidationResult(isValid: false, errors: ["Name is required"])
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(invalid.errors, ["Name is required"])
    }

    func testBloodTestModelValidityForManagerInputs() {
        let validBloodTest = BloodTestResult(
            testDate: Date(),
            results: [BloodTestItem(name: "Glucose", value: "95")]
        )
        XCTAssertTrue(validBloodTest.isValid)

        let invalidBloodTest = BloodTestResult(testDate: Date(), results: [])
        XCTAssertFalse(invalidBloodTest.isValid)
    }

    func testAnyHealthDataDecodesPersonalInfo() throws {
        let info = PersonalHealthInfo(name: "Jane Doe", gender: .female)
        let anyHealthData = try AnyHealthData(info)

        XCTAssertEqual(anyHealthData.type, .personalInfo)

        let decoded = try anyHealthData.decode(as: PersonalHealthInfo.self)
        XCTAssertEqual(decoded.name, "Jane Doe")
        XCTAssertEqual(decoded.gender, .female)
    }
}
