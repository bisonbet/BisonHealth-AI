import Foundation
import HealthKit

// MARK: - HealthKit Manager
@MainActor
class HealthKitManager: ObservableObject {

    // MARK: - Shared Instance
    static let shared = HealthKitManager()

    // MARK: - Published Properties
    @Published var isAuthorized = false {
        didSet {
            UserDefaults.standard.set(isAuthorized, forKey: "healthKitIsAuthorized")
        }
    }
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isSyncing = false
    @Published var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                UserDefaults.standard.set(date, forKey: "healthKitLastSyncDate")
            }
        }
    }
    @Published var syncError: Error?
    @Published var lastSyncStats: SyncStatistics?

    // MARK: - Dependencies
    private let healthStore = HKHealthStore()
    private let logger = Logger.shared

    // MARK: - Constants
    private let bloodPressureMatchingWindow: TimeInterval = 60 // 1 minute
    private let sleepQueryDateRange: Int = -30 // Last 30 days
    private let secondsPerMinute: Double = 60

    // MARK: - HealthKit Data Types
    private let readTypes: Set<HKSampleType> = {
        var types = Set<HKSampleType>()

        // Characteristics (these are HKObjectType, not HKSampleType)
        // We'll handle these separately

        // Vitals
        if let bloodPressureSystolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) {
            types.insert(bloodPressureSystolic)
        }
        if let bloodPressureDiastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(bloodPressureDiastolic)
        }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let bodyTemp = HKObjectType.quantityType(forIdentifier: .bodyTemperature) {
            types.insert(bodyTemp)
        }
        if let oxygenSat = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(oxygenSat)
        }
        if let respiratoryRate = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respiratoryRate)
        }
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        if let height = HKObjectType.quantityType(forIdentifier: .height) {
            types.insert(height)
        }

        // Sleep
        if let sleepAnalysis = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepAnalysis)
        }

        return types
    }()

    private let characteristicTypes: Set<HKCharacteristicType> = {
        var types = Set<HKCharacteristicType>()

        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSex)
        }
        if let bloodType = HKObjectType.characteristicType(forIdentifier: .bloodType) {
            types.insert(bloodType)
        }
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }

        return types
    }()

    // MARK: - Initialization
    private init() {
        // Load persisted state
        isAuthorized = UserDefaults.standard.bool(forKey: "healthKitIsAuthorized")
        lastSyncDate = UserDefaults.standard.object(forKey: "healthKitLastSyncDate") as? Date

        // Check current authorization status
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Check if HealthKit is available on this device
    func isHealthKitAvailable() -> Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    /// Check current authorization status
    private func checkAuthorizationStatus() {
        guard isHealthKitAvailable() else {
            logger.warning("HealthKit is not available on this device")
            return
        }

        // Check if we have authorization for at least one type
        // Note: We only update isAuthorized if we have a definitive answer
        // Otherwise, we keep the persisted value from previous successful syncs
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let status = healthStore.authorizationStatus(for: heartRateType)
            authorizationStatus = status

            // Only update isAuthorized if we have a definitive status
            // .sharingDenied means definitely not authorized
            // .sharingAuthorized means definitely authorized
            // .notDetermined means we don't know yet - keep existing value
            if status == .sharingDenied {
                isAuthorized = false
            } else if status == .sharingAuthorized {
                isAuthorized = true
            }
            // If .notDetermined, keep the persisted value
        }
    }

    /// Request authorization to read health data
    func requestAuthorization() async throws {
        guard isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }

        logger.info("Requesting HealthKit authorization")

        // Combine all types for authorization request
        var allTypes = Set<HKObjectType>()
        allTypes.formUnion(readTypes)
        allTypes.formUnion(characteristicTypes)

        try await healthStore.requestAuthorization(toShare: [], read: allTypes)

        checkAuthorizationStatus()
        logger.info("HealthKit authorization completed")
    }

    // MARK: - Data Sync

    /// Sync all health data from Apple Health
    func syncAllHealthData() async throws -> SyncedHealthData {
        guard isHealthKitAvailable() else {
            throw HealthKitError.notAvailable
        }

        isSyncing = true
        syncError = nil

        let startTime = Date()
        var stats = SyncStatistics()
        logger.info("Starting HealthKit sync")

        do {
            var syncedData = SyncedHealthData()

            // Sync characteristics (one-time values)
            do {
                syncedData.dateOfBirth = try readDateOfBirth()
                if syncedData.dateOfBirth != nil {
                    stats.successfulDataTypes += 1
                }
            } catch {
                logger.warning("Failed to read date of birth from HealthKit: \(error.localizedDescription)")
                stats.failedDataTypes.append("Date of Birth")
            }

            do {
                syncedData.biologicalSex = try readBiologicalSex()
                if syncedData.biologicalSex != nil {
                    stats.successfulDataTypes += 1
                }
            } catch {
                logger.warning("Failed to read biological sex from HealthKit: \(error.localizedDescription)")
                stats.failedDataTypes.append("Biological Sex")
            }

            do {
                syncedData.bloodType = try readBloodType()
                if syncedData.bloodType != nil {
                    stats.successfulDataTypes += 1
                }
            } catch {
                logger.warning("Failed to read blood type from HealthKit: \(error.localizedDescription)")
                stats.failedDataTypes.append("Blood Type")
            }

            do {
                syncedData.height = try await readLatestHeight()
                if syncedData.height != nil {
                    stats.successfulDataTypes += 1
                }
            } catch {
                logger.warning("Failed to read height from HealthKit: \(error.localizedDescription)")
                stats.failedDataTypes.append("Height")
            }

            // Sync vitals and sleep in parallel for better performance
            async let bloodPressure = readBloodPressure(limit: 7)
            async let heartRate = readHeartRate(limit: 7)
            async let bodyTemp = readBodyTemperature(limit: 7)
            async let oxygenSat = readOxygenSaturation(limit: 7)
            async let respiratoryRate = readRespiratoryRate(limit: 7)
            async let weight = readWeight(limit: 7)
            async let sleep = readSleepAnalysis(limit: 7)

            // Await all results and track statistics
            syncedData.bloodPressureReadings = try await bloodPressure
            stats.totalReadings += syncedData.bloodPressureReadings.count
            if !syncedData.bloodPressureReadings.isEmpty { stats.successfulDataTypes += 1 }

            syncedData.heartRateReadings = try await heartRate
            stats.totalReadings += syncedData.heartRateReadings.count
            if !syncedData.heartRateReadings.isEmpty { stats.successfulDataTypes += 1 }

            syncedData.bodyTemperatureReadings = try await bodyTemp
            stats.totalReadings += syncedData.bodyTemperatureReadings.count
            if !syncedData.bodyTemperatureReadings.isEmpty { stats.successfulDataTypes += 1 }

            syncedData.oxygenSaturationReadings = try await oxygenSat
            stats.totalReadings += syncedData.oxygenSaturationReadings.count
            if !syncedData.oxygenSaturationReadings.isEmpty { stats.successfulDataTypes += 1 }

            syncedData.respiratoryRateReadings = try await respiratoryRate
            stats.totalReadings += syncedData.respiratoryRateReadings.count
            if !syncedData.respiratoryRateReadings.isEmpty { stats.successfulDataTypes += 1 }

            syncedData.weightReadings = try await weight
            stats.totalReadings += syncedData.weightReadings.count
            if !syncedData.weightReadings.isEmpty { stats.successfulDataTypes += 1 }

            syncedData.sleepData = try await sleep
            stats.totalReadings += syncedData.sleepData.count
            if !syncedData.sleepData.isEmpty { stats.successfulDataTypes += 1 }

            stats.syncDuration = Date().timeIntervalSince(startTime)
            stats.timestamp = Date()
            lastSyncStats = stats
            lastSyncDate = Date()
            isSyncing = false

            // Update authorization status after successful sync
            // If we successfully synced data, we must be authorized
            if stats.totalReadings > 0 {
                isAuthorized = true
                authorizationStatus = .sharingAuthorized
            }

            logger.info("HealthKit sync completed: \(stats.summary)")

            return syncedData

        } catch {
            isSyncing = false
            syncError = error
            logger.error("HealthKit sync failed", error: error)
            throw error
        }
    }

    // MARK: - Characteristics (One-time values)

    private func readDateOfBirth() throws -> Date? {
        guard let dateOfBirth = try? healthStore.dateOfBirthComponents() else {
            return nil
        }
        return Calendar.current.date(from: dateOfBirth)
    }

    private func readBiologicalSex() throws -> Gender? {
        guard let biologicalSex = try? healthStore.biologicalSex() else {
            return nil
        }

        switch biologicalSex.biologicalSex {
        case .male:
            return .male
        case .female:
            return .female
        case .other:
            return .other
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }

    private func readBloodType() throws -> BloodType? {
        guard let bloodType = try? healthStore.bloodType() else {
            return nil
        }

        switch bloodType.bloodType {
        case .aPositive: return .aPositive
        case .aNegative: return .aNegative
        case .bPositive: return .bPositive
        case .bNegative: return .bNegative
        case .abPositive: return .abPositive
        case .abNegative: return .abNegative
        case .oPositive: return .oPositive
        case .oNegative: return .oNegative
        case .notSet: return nil
        @unknown default: return nil
        }
    }

    private func readLatestHeight() async throws -> Measurement<UnitLength>? {
        guard let heightType = HKObjectType.quantityType(forIdentifier: .height) else {
            return nil
        }

        let readings = try await fetchQuantitySamples(for: heightType, limit: 1)
        guard let latest = readings.first else { return nil }

        let meters = latest.quantity.doubleValue(for: .meter())
        return Measurement(value: meters, unit: .meters)
    }

    // MARK: - Vitals (Time-series data)

    private func readBloodPressure(limit: Int) async throws -> [VitalReading] {
        guard let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return []
        }

        let systolicSamples = try await fetchQuantitySamples(for: systolicType, limit: limit)
        let diastolicSamples = try await fetchQuantitySamples(for: diastolicType, limit: limit)

        // Optimize blood pressure matching using dictionary-based timestamp indexing
        // Group diastolic samples by their timestamp rounded to the nearest minute
        var diastolicByMinute: [Int: [HKQuantitySample]] = [:]
        for sample in diastolicSamples {
            let minuteKey = Int(sample.startDate.timeIntervalSince1970 / bloodPressureMatchingWindow)
            diastolicByMinute[minuteKey, default: []].append(sample)
        }

        var readings: [VitalReading] = []
        var usedDiastolicIndices = Set<Int>()

        for systolicSample in systolicSamples {
            let systolicMinuteKey = Int(systolicSample.startDate.timeIntervalSince1970 / bloodPressureMatchingWindow)

            // Check the same minute bucket and adjacent buckets for matches
            var foundMatch = false
            for minuteOffset in [-1, 0, 1] {
                guard let candidates = diastolicByMinute[systolicMinuteKey + minuteOffset] else { continue }

                // Find the closest unused diastolic reading within the matching window
                for (index, diastolicSample) in diastolicSamples.enumerated() {
                    guard !usedDiastolicIndices.contains(index),
                          candidates.contains(diastolicSample),
                          abs(diastolicSample.startDate.timeIntervalSince(systolicSample.startDate)) < bloodPressureMatchingWindow else {
                        continue
                    }

                    let systolic = systolicSample.quantity.doubleValue(for: .millimeterOfMercury())
                    let diastolic = diastolicSample.quantity.doubleValue(for: .millimeterOfMercury())

                    let reading = VitalReading(
                        value: systolic,
                        unit: "mmHg",
                        timestamp: systolicSample.startDate,
                        source: .appleHealth,
                        systolic: systolic,
                        diastolic: diastolic
                    )

                    // Only add if valid
                    if reading.isValid() {
                        readings.append(reading)
                        usedDiastolicIndices.insert(index)
                        foundMatch = true
                        break
                    } else {
                        logger.warning("Skipping invalid blood pressure reading: \(systolic)/\(diastolic) mmHg")
                    }
                }

                if foundMatch { break }
            }
        }

        return readings
    }

    private func readHeartRate(limit: Int) async throws -> [VitalReading] {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return []
        }

        let samples = try await fetchQuantitySamples(for: heartRateType, limit: limit)

        return samples.compactMap { sample in
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let reading = VitalReading(
                value: bpm,
                unit: "bpm",
                timestamp: sample.startDate,
                source: .appleHealth
            )
            if reading.isValid() {
                return reading
            } else {
                logger.warning("Skipping invalid heart rate reading: \(bpm) bpm")
                return nil
            }
        }
    }

    private func readBodyTemperature(limit: Int) async throws -> [VitalReading] {
        guard let bodyTempType = HKObjectType.quantityType(forIdentifier: .bodyTemperature) else {
            return []
        }

        let samples = try await fetchQuantitySamples(for: bodyTempType, limit: limit)

        return samples.compactMap { sample in
            let fahrenheit = sample.quantity.doubleValue(for: .degreeFahrenheit())
            let reading = VitalReading(
                value: fahrenheit,
                unit: "°F",
                timestamp: sample.startDate,
                source: .appleHealth
            )
            if reading.isValid() {
                return reading
            } else {
                logger.warning("Skipping invalid body temperature reading: \(fahrenheit) °F")
                return nil
            }
        }
    }

    private func readOxygenSaturation(limit: Int) async throws -> [VitalReading] {
        guard let oxygenType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            return []
        }

        let samples = try await fetchQuantitySamples(for: oxygenType, limit: limit)

        return samples.compactMap { sample in
            let percentage = sample.quantity.doubleValue(for: .percent()) * 100
            let reading = VitalReading(
                value: percentage,
                unit: "%",
                timestamp: sample.startDate,
                source: .appleHealth
            )
            if reading.isValid() {
                return reading
            } else {
                logger.warning("Skipping invalid oxygen saturation reading: \(percentage) %")
                return nil
            }
        }
    }

    private func readRespiratoryRate(limit: Int) async throws -> [VitalReading] {
        guard let respRateType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else {
            return []
        }

        let samples = try await fetchQuantitySamples(for: respRateType, limit: limit)

        return samples.compactMap { sample in
            let breathsPerMin = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let reading = VitalReading(
                value: breathsPerMin,
                unit: "br/min",
                timestamp: sample.startDate,
                source: .appleHealth
            )
            if reading.isValid() {
                return reading
            } else {
                logger.warning("Skipping invalid respiratory rate reading: \(breathsPerMin) br/min")
                return nil
            }
        }
    }

    private func readWeight(limit: Int) async throws -> [VitalReading] {
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            return []
        }

        let samples = try await fetchQuantitySamples(for: weightType, limit: limit)

        return samples.compactMap { sample in
            let pounds = sample.quantity.doubleValue(for: .pound())
            let reading = VitalReading(
                value: pounds,
                unit: "lbs",
                timestamp: sample.startDate,
                source: .appleHealth
            )
            if reading.isValid() {
                return reading
            } else {
                logger.warning("Skipping invalid weight reading: \(pounds) lbs")
                return nil
            }
        }
    }

    // MARK: - Sleep Data

    private func readSleepAnalysis(limit: Int) async throws -> [SleepData] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        // Query for sleep samples (to ensure we get 7 complete nights)
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: sleepQueryDateRange, to: endDate) ?? endDate

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }

        // Group sleep samples by date
        let groupedSleep = Dictionary(grouping: samples) { sample -> Date in
            let calendar = Calendar.current
            return calendar.startOfDay(for: sample.startDate)
        }

        // Convert to SleepData, taking the most recent 'limit' nights
        var sleepDataArray: [SleepData] = []

        for (date, samplesForDate) in groupedSleep.sorted(by: { $0.key > $1.key }).prefix(limit) {
            // Filter for actual sleep (not in bed)
            let sleepSamples = samplesForDate.filter { sample in
                if #available(iOS 16.0, *) {
                    return sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                } else {
                    return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
                }
            }

            guard !sleepSamples.isEmpty else { continue }

            // Calculate total sleep time
            let totalSleepSeconds = sleepSamples.reduce(0) { total, sample in
                total + sample.endDate.timeIntervalSince(sample.startDate)
            }
            let totalSleepMinutes = Int(totalSleepSeconds / secondsPerMinute)

            // Get start and end times
            let startTime = sleepSamples.map { $0.startDate }.min() ?? date
            let endTime = sleepSamples.map { $0.endDate }.max() ?? date

            // Calculate sleep stages if available (iOS 16+)
            var deepSleep: Int?
            var remSleep: Int?
            var coreSleep: Int?
            var awake: Int?

            if #available(iOS 16.0, *) {
                deepSleep = calculateSleepStageMinutes(samples: samplesForDate, stage: .asleepDeep)
                remSleep = calculateSleepStageMinutes(samples: samplesForDate, stage: .asleepREM)
                coreSleep = calculateSleepStageMinutes(samples: samplesForDate, stage: .asleepCore)
                awake = calculateSleepStageMinutes(samples: samplesForDate, stage: .awake)
            }

            // Calculate in bed time (includes all sleep + awake in bed)
            let inBedSamples = samplesForDate.filter { sample in
                if #available(iOS 16.0, *) {
                    return sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.awake.rawValue
                } else {
                    return sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue ||
                           sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
                }
            }

            let inBedSeconds = inBedSamples.reduce(0) { total, sample in
                total + sample.endDate.timeIntervalSince(sample.startDate)
            }
            let inBedMinutes = Int(inBedSeconds / secondsPerMinute)

            sleepDataArray.append(SleepData(
                date: date,
                startTime: startTime,
                endTime: endTime,
                totalSleepMinutes: totalSleepMinutes,
                source: .appleHealth,
                deepSleepMinutes: deepSleep,
                remSleepMinutes: remSleep,
                coreSleepMinutes: coreSleep,
                awakeMinutes: awake,
                inBedMinutes: inBedMinutes > 0 ? inBedMinutes : nil
            ))
        }

        return sleepDataArray.sorted { $0.date > $1.date }
    }

    @available(iOS 16.0, *)
    private func calculateSleepStageMinutes(samples: [HKCategorySample], stage: HKCategoryValueSleepAnalysis) -> Int? {
        let stageSamples = samples.filter { $0.value == stage.rawValue }
        guard !stageSamples.isEmpty else { return nil }

        let totalSeconds = stageSamples.reduce(0) { total, sample in
            total + sample.endDate.timeIntervalSince(sample.startDate)
        }
        return Int(totalSeconds / secondsPerMinute)
    }

    // MARK: - Helper Methods

    private func fetchQuantitySamples(for quantityType: HKQuantityType, limit: Int) async throws -> [HKQuantitySample] {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Supporting Types

struct SyncedHealthData {
    var dateOfBirth: Date?
    var biologicalSex: Gender?
    var bloodType: BloodType?
    var height: Measurement<UnitLength>?

    var bloodPressureReadings: [VitalReading] = []
    var heartRateReadings: [VitalReading] = []
    var bodyTemperatureReadings: [VitalReading] = []
    var oxygenSaturationReadings: [VitalReading] = []
    var respiratoryRateReadings: [VitalReading] = []
    var weightReadings: [VitalReading] = []

    var sleepData: [SleepData] = []
}

struct SyncStatistics {
    var successfulDataTypes: Int = 0
    var failedDataTypes: [String] = []
    var totalReadings: Int = 0
    var invalidReadingsSkipped: Int = 0
    var syncDuration: TimeInterval = 0
    var timestamp: Date = Date()

    var summary: String {
        if failedDataTypes.isEmpty {
            return "Synced \(totalReadings) readings from \(successfulDataTypes) data types"
        } else {
            return "Synced \(totalReadings) readings. Failed: \(failedDataTypes.joined(separator: ", "))"
        }
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case notAuthorized
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "Not authorized to access HealthKit data"
        case .readFailed(let details):
            return "Failed to read HealthKit data: \(details)"
        }
    }
}
