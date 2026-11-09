import XCTest
@testable import HealthApp

@MainActor
final class HealthDataManagerTests: XCTestCase {
    private var containers: [TestContainer] = []

    override func tearDown() async throws {
        containers.forEach { $0.remove() }
        containers.removeAll()
        try await super.tearDown()
    }

    /// Not `HealthDataManager.shared`, which loads from the app's own database on first use.
    private func makeManager() throws -> HealthDataManager {
        let container = try TestContainer()
        containers.append(container)
        return HealthDataManager(
            databaseManager: try container.makeDatabaseManager(),
            fileSystemManager: try container.makeFileSystemManager(),
            automaticallyLoad: false
        )
    }

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
    func testRepeatOfTheSamePanelWithDifferentValuesIsNotADuplicate() throws {
        let manager = try makeManager()
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

    func testTheSameReportImportedTwiceIsStillADuplicate() throws {
        let manager = try makeManager()
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

    // MARK: - HealthKit merge

    /// A reading typed in on the entry screen can carry the "Apple Health" source. The old
    /// merge kept only `.manual` readings, so the next sync deleted it.
    func testHealthKitMergeKeepsStoredNonManualReadings() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let typedAsAppleHealth = VitalReading(value: 72, unit: "bpm", timestamp: base, source: .appleHealth)
        let fresh = VitalReading(value: 70, unit: "bpm", timestamp: base.addingTimeInterval(3600), source: .appleHealth)

        let merged = HealthDataManager.mergeVitalReadings(
            stored: [typedAsAppleHealth], healthKit: [fresh], limit: 7, conflictInterval: 300
        )

        XCTAssertEqual(merged.map(\.id), [fresh.id, typedAsAppleHealth.id])
    }

    func testHealthKitMergeDoesNotDuplicateAReadingItAlreadyHas() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let stored = VitalReading(value: 120, unit: "lbs", timestamp: base, source: .manual)
        let sameMoment = VitalReading(value: 121, unit: "lbs", timestamp: base.addingTimeInterval(60), source: .appleHealth)

        let merged = HealthDataManager.mergeVitalReadings(
            stored: [stored], healthKit: [sameMoment], limit: 7, conflictInterval: 300
        )

        XCTAssertEqual(merged.map(\.id), [stored.id], "The stored reading wins inside the conflict window")
    }

    /// HealthKit recomputes a night's totals from its current samples each sync; stages can
    /// arrive after the first one. A night it imported earlier must be refreshed, while a
    /// night the user entered by hand is kept.
    func testHealthKitSleepMergeRefreshesImportedNightsButKeepsManualOnes() {
        let calendar = Calendar(identifier: .gregorian)
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let tuesday = monday.addingTimeInterval(86_400)
        func night(_ date: Date, _ minutes: Int, _ source: VitalSource) -> SleepData {
            SleepData(date: date, startTime: date, endTime: date.addingTimeInterval(Double(minutes) * 60),
                      totalSleepMinutes: minutes, source: source)
        }
        let importedMonday = night(monday, 300, .appleHealth)
        let manualTuesday = night(tuesday, 480, .manual)
        let refreshedMonday = night(monday, 420, .appleHealth)
        let healthKitTuesday = night(tuesday, 200, .appleHealth)

        let merged = HealthDataManager.mergeSleepData(
            stored: [importedMonday, manualTuesday],
            healthKit: [refreshedMonday, healthKitTuesday],
            limit: 7,
            calendar: calendar
        )

        XCTAssertEqual(merged.map(\.id), [manualTuesday.id, refreshedMonday.id])
    }

    func testHealthKitMergeRefreshesAnImportedReading() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let imported = VitalReading(value: 98, unit: "%", timestamp: base, source: .appleHealth)
        let refreshed = VitalReading(value: 97, unit: "%", timestamp: base, source: .appleHealth)

        let merged = HealthDataManager.mergeVitalReadings(
            stored: [imported], healthKit: [refreshed], limit: 7, conflictInterval: 300
        )

        XCTAssertEqual(merged.map(\.id), [refreshed.id])
    }

    /// HealthKit returns samples newest first. Readings minutes apart in one batch must leave
    /// the newest, not let each older sample replace the one before it.
    func testHealthKitMergeKeepsTheNewestReadingOfABatchCluster() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let at1002 = VitalReading(value: 80, unit: "bpm", timestamp: base.addingTimeInterval(120), source: .appleHealth)
        let at1001 = VitalReading(value: 79, unit: "bpm", timestamp: base.addingTimeInterval(60), source: .appleHealth)
        let at1000 = VitalReading(value: 78, unit: "bpm", timestamp: base, source: .appleHealth)
        let storedAt1001 = VitalReading(value: 70, unit: "bpm", timestamp: base.addingTimeInterval(60), source: .appleHealth)

        let fromEmpty = HealthDataManager.mergeVitalReadings(
            stored: [], healthKit: [at1002, at1001, at1000], limit: 7, conflictInterval: 300
        )
        XCTAssertEqual(fromEmpty.map(\.id), [at1002.id])

        let overStored = HealthDataManager.mergeVitalReadings(
            stored: [storedAt1001], healthKit: [at1002, at1001, at1000], limit: 7, conflictInterval: 300
        )
        XCTAssertEqual(overStored.map(\.id), [at1002.id])
    }

    func testWeightReadingIsConvertedFromItsOwnUnit() {
        let kilograms = VitalReading(value: 70, unit: "kg", timestamp: Date(), source: .manual)
        let pounds = VitalReading(value: 154.3, unit: "lbs", timestamp: Date(), source: .manual)

        XCTAssertEqual(HealthDataManager.weightMeasurement(of: kilograms).converted(to: .kilograms).value, 70, accuracy: 0.001)
        XCTAssertEqual(HealthDataManager.weightMeasurement(of: pounds).converted(to: .kilograms).value, 70, accuracy: 0.05)
    }
}
