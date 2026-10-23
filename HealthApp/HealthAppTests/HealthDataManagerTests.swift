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

    /// Two runs of the same panel are not the same report.
    ///
    /// The duplicate guard compared only which analytes were present and how many —
    /// never their values — so every repeat of a standard panel scored ~100% similar.
    /// With the import-date fallback putting undated reports inside the 24-hour window,
    /// importing a stack of historical labs saved the first and discarded the rest.
    func testRepeatOfTheSamePanelWithDifferentValuesIsNotADuplicate() {
        let manager = HealthDataManager.shared
        let panel2023 = BloodTestResult(testDate: Date(), results: [
            BloodTestItem(name: "Glucose", value: "95"),
            BloodTestItem(name: "Creatinine", value: "0.9"),
            BloodTestItem(name: "Sodium", value: "140")
        ])
        let panel2024 = BloodTestResult(testDate: Date(), results: [
            BloodTestItem(name: "Glucose", value: "112"),
            BloodTestItem(name: "Creatinine", value: "1.1"),
            BloodTestItem(name: "Sodium", value: "138")
        ])

        XCTAssertLessThan(
            manager.calculateBloodTestSimilarity(panel2023, panel2024),
            0.8,
            "Same analytes with different readings must not be treated as a duplicate"
        )
    }

    func testTheSameReportImportedTwiceIsStillADuplicate() {
        let manager = HealthDataManager.shared
        let results = [
            BloodTestItem(name: "Glucose", value: "95"),
            BloodTestItem(name: "Creatinine", value: "0.9")
        ]
        let first = BloodTestResult(testDate: Date(), results: results)
        let second = BloodTestResult(testDate: Date(), results: results)

        XCTAssertGreaterThan(
            manager.calculateBloodTestSimilarity(first, second),
            0.8,
            "Identical readings are what actually make two reports the same report"
        )
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
