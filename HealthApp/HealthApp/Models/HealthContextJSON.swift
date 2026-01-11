//
//  HealthContextJSON.swift
//  HealthApp
//
//  JSON builder for health data context
//  Converts ChatContext to structured JSON for AI providers
//

import Foundation

// MARK: - Health Context JSON Builder
struct HealthContextJSON {

    // MARK: - Main Builder

    /// Builds JSON representation of ChatContext
    /// - Parameter context: The ChatContext to convert
    /// - Returns: Dictionary ready for JSON serialization
    static func buildContextJSON(from context: ChatContext) -> [String: Any] {
        var json: [String: Any] = [:]

        // Timestamp
        json["timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Selected data types
        let selectedTypes = context.selectedDataTypes.map { $0.jsonKey }
        json["selected_types"] = selectedTypes

        // Personal Information
        if let personalInfo = context.personalInfo,
           context.selectedDataTypes.contains(.personalInfo) {
            json["personal_info"] = encodePersonalInfo(personalInfo)
        }

        // Blood Tests (only those marked for inclusion)
        if context.selectedDataTypes.contains(.bloodTest) {
            let includedTests = context.bloodTests.filter { $0.includeInAIContext }
            if !includedTests.isEmpty {
                // Take only the 5 most recent tests
                let recentTests = Array(includedTests
                    .sorted { $0.testDate > $1.testDate }
                    .prefix(5))
                json["blood_tests"] = recentTests.map { encodeBloodTest($0) }
            }
        }

        // Medical Documents
        if !context.medicalDocuments.isEmpty {
            // Sort by priority (highest first), then by date (newest first)
            let sortedDocs = context.medicalDocuments.sorted { doc1, doc2 in
                if doc1.contextPriority != doc2.contextPriority {
                    return doc1.contextPriority > doc2.contextPriority
                }
                guard let date1 = doc1.documentDate, let date2 = doc2.documentDate else {
                    return doc1.documentDate != nil
                }
                return date1 > date2
            }
            json["medical_documents"] = sortedDocs.map { encodeDocument($0) }
        }

        return json
    }

    // MARK: - Personal Information Encoder

    private static func encodePersonalInfo(_ info: PersonalHealthInfo) -> [String: Any] {
        var json: [String: Any] = [:]

        // Basic demographics
        if let name = info.name { json["name"] = name }

        if let dob = info.dateOfBirth {
            json["dob"] = ISO8601DateFormatter().string(from: dob)

            // Calculate age
            let calendar = Calendar.current
            let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
            if let age = ageComponents.year {
                json["age"] = age
            }
        }

        if let gender = info.gender { json["gender"] = gender.jsonValue }
        if let bloodType = info.bloodType { json["blood_type"] = bloodType.jsonValue }

        // Height and Weight
        if let height = info.height {
            json["height"] = height.jsonValue
        }
        if let weight = info.weight {
            json["weight"] = weight.jsonValue
        }

        // Allergies
        if !info.allergies.isEmpty {
            json["allergies"] = info.allergies
        }

        // Medications
        if !info.medications.isEmpty {
            json["medications"] = info.medications.map { encodeMedication($0) }
        }

        // Supplements
        if !info.supplements.isEmpty {
            json["supplements"] = info.supplements.map { encodeSupplement($0) }
        }

        // Medical Conditions
        if !info.personalMedicalHistory.isEmpty {
            json["conditions"] = info.personalMedicalHistory.map { encodeCondition($0) }
        }

        // Vitals
        let vitals = encodeVitals(info)
        if !vitals.isEmpty {
            json["vitals"] = vitals
        }

        // Sleep Data
        if !info.sleepData.isEmpty {
            json["sleep"] = encodeSleep(info.sleepData)
        }

        return json
    }

    // MARK: - Medication Encoder

    private static func encodeMedication(_ med: Medication) -> [String: Any] {
        var json: [String: Any] = [:]

        json["name"] = med.name

        // Dosage
        var dosageJson: [String: Any] = [:]
        if med.dosage.value > 0 {
            dosageJson["amount"] = med.dosage.value.jsonValue
            dosageJson["unit"] = med.dosage.unit.jsonValue
        }
        if !dosageJson.isEmpty {
            json["dosage"] = dosageJson
        }

        // Frequency
        json["frequency"] = med.frequency.jsonValue()

        if let prescribedBy = med.prescribedBy { json["prescribed_by"] = prescribedBy }

        if let startDate = med.startDate {
            json["start_date"] = ISO8601DateFormatter().string(from: startDate)
        }

        if let endDate = med.endDate {
            json["end_date"] = endDate.jsonValue()
        }

        json["status"] = med.isOngoing ? "ongoing" : "completed"

        if let notes = med.notes { json["notes"] = notes }

        return json
    }

    // MARK: - Supplement Encoder

    private static func encodeSupplement(_ supplement: Supplement) -> [String: Any] {
        var json: [String: Any] = [:]

        json["name"] = supplement.name
        json["category"] = supplement.category.jsonValue

        // Dosage
        var dosageJson: [String: Any] = [:]
        if supplement.dosage.value > 0 {
            dosageJson["amount"] = supplement.dosage.value.jsonValue
            dosageJson["unit"] = supplement.dosage.unit.jsonValue
        }
        if !dosageJson.isEmpty {
            json["dosage"] = dosageJson
        }

        // Frequency
        json["frequency"] = supplement.frequency.jsonValue()

        if let startDate = supplement.startDate {
            json["start_date"] = ISO8601DateFormatter().string(from: startDate)
        }

        if let notes = supplement.notes { json["notes"] = notes }

        return json
    }

    // MARK: - Medical Condition Encoder

    private static func encodeCondition(_ condition: MedicalCondition) -> [String: Any] {
        var json: [String: Any] = [:]

        json["name"] = condition.name
        json["status"] = condition.status.jsonValue

        if let severity = condition.severity {
            json["severity"] = severity.jsonValue
        }

        if let diagnosedDate = condition.diagnosedDate {
            json["diagnosed_date"] = ISO8601DateFormatter().string(from: diagnosedDate)
        }

        if let treatingPhysician = condition.treatingPhysician {
            json["treating_physician"] = treatingPhysician
        }

        if let notes = condition.notes { json["notes"] = notes }

        return json
    }

    // MARK: - Vitals Encoder

    private static func encodeVitals(_ info: PersonalHealthInfo) -> [String: Any] {
        var json: [String: Any] = [:]

        // Blood Pressure (last 3 readings)
        if !info.bloodPressureReadings.isEmpty {
            let readings = Array(info.bloodPressureReadings
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3))

            var bpJson: [String: Any] = [:]
            bpJson["readings"] = readings.map { reading -> [String: Any] in
                var r: [String: Any] = [:]
                if let systolic = reading.systolic, let diastolic = reading.diastolic {
                    r["systolic"] = systolic.jsonValue
                    r["diastolic"] = diastolic.jsonValue
                }
                r["timestamp"] = ISO8601DateFormatter().string(from: reading.timestamp)
                r["source"] = reading.source.jsonValue
                return r
            }

            // Calculate average
            if let firstReading = readings.first,
               let systolic = firstReading.systolic,
               let diastolic = firstReading.diastolic {
                bpJson["average"] = "\(Int(systolic))/\(Int(diastolic))"
            }

            json["blood_pressure"] = bpJson
        }

        // Heart Rate (last 3 readings + average)
        if !info.heartRateReadings.isEmpty {
            let readings = Array(info.heartRateReadings
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3))

            var hrJson: [String: Any] = [:]
            hrJson["readings"] = readings.map { reading -> [String: Any] in
                var r: [String: Any] = [:]
                r["bpm"] = reading.value.jsonValue
                r["timestamp"] = ISO8601DateFormatter().string(from: reading.timestamp)
                r["source"] = reading.source.jsonValue
                return r
            }

            // Calculate average
            let avgBPM = readings.map { $0.value }.reduce(0, +) / Double(readings.count)
            hrJson["average"] = Int(avgBPM)

            json["heart_rate"] = hrJson
        }

        // Body Temperature (last 3 readings)
        if !info.bodyTemperatureReadings.isEmpty {
            let readings = Array(info.bodyTemperatureReadings
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3))

            var tempJson: [String: Any] = [:]
            tempJson["readings"] = readings.map { reading -> [String: Any] in
                var r: [String: Any] = [:]
                r["fahrenheit"] = reading.value.jsonValue
                r["timestamp"] = ISO8601DateFormatter().string(from: reading.timestamp)
                r["source"] = reading.source.jsonValue
                return r
            }
            json["body_temperature"] = tempJson
        }

        // Oxygen Saturation (last 3 readings + average)
        if !info.oxygenSaturationReadings.isEmpty {
            let readings = Array(info.oxygenSaturationReadings
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3))

            var o2Json: [String: Any] = [:]
            o2Json["readings"] = readings.map { reading -> [String: Any] in
                var r: [String: Any] = [:]
                r["percent"] = reading.value.jsonValue
                r["timestamp"] = ISO8601DateFormatter().string(from: reading.timestamp)
                r["source"] = reading.source.jsonValue
                return r
            }

            // Calculate average
            let avgO2 = readings.map { $0.value }.reduce(0, +) / Double(readings.count)
            o2Json["average"] = Int(avgO2)

            json["oxygen_saturation"] = o2Json
        }

        // Respiratory Rate (last 3 readings)
        if !info.respiratoryRateReadings.isEmpty {
            let readings = Array(info.respiratoryRateReadings
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3))

            var rrJson: [String: Any] = [:]
            rrJson["readings"] = readings.map { reading -> [String: Any] in
                var r: [String: Any] = [:]
                r["breaths_per_min"] = reading.value.jsonValue
                r["timestamp"] = ISO8601DateFormatter().string(from: reading.timestamp)
                r["source"] = reading.source.jsonValue
                return r
            }
            json["respiratory_rate"] = rrJson
        }

        // Weight (last 5 readings)
        if !info.weightReadings.isEmpty {
            let readings = Array(info.weightReadings
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(5))

            var weightJson: [String: Any] = [:]
            weightJson["readings"] = readings.map { reading -> [String: Any] in
                var r: [String: Any] = [:]
                r["pounds"] = reading.value.jsonValue
                r["timestamp"] = ISO8601DateFormatter().string(from: reading.timestamp)
                r["source"] = reading.source.jsonValue
                return r
            }
            json["weight_history"] = weightJson
        }

        return json
    }

    // MARK: - Sleep Data Encoder

    private static func encodeSleep(_ sleepData: [SleepData]) -> [String: Any] {
        var json: [String: Any] = [:]

        // Last 7 nights
        let recentSleep = Array(sleepData
            .sorted { $0.date > $1.date }
            .prefix(7))

        json["readings"] = recentSleep.map { sleep -> [String: Any] in
            var s: [String: Any] = [:]

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            s["date"] = formatter.string(from: sleep.date)

            s["total_minutes"] = sleep.totalSleepMinutes

            if let deepMinutes = sleep.deepSleepMinutes { s["deep_minutes"] = deepMinutes }
            if let remMinutes = sleep.remSleepMinutes { s["rem_minutes"] = remMinutes }
            if let coreMinutes = sleep.coreSleepMinutes { s["core_minutes"] = coreMinutes }
            if let awakeMinutes = sleep.awakeMinutes { s["awake_minutes"] = awakeMinutes }

            s["source"] = sleep.source.jsonValue

            return s
        }

        // Calculate average sleep hours
        if !recentSleep.isEmpty {
            let totalMinutes = recentSleep.map { $0.totalSleepMinutes }.reduce(0, +)
            let avgHours = Double(totalMinutes) / Double(recentSleep.count) / 60.0
            json["average_hours"] = round(avgHours * 10) / 10  // Round to 1 decimal
        }

        return json
    }

    // MARK: - Blood Test Encoder

    private static func encodeBloodTest(_ test: BloodTestResult) -> [String: Any] {
        var json: [String: Any] = [:]

        // Test date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        json["test_date"] = formatter.string(from: test.testDate)

        if let laboratory = test.laboratoryName { json["laboratory"] = laboratory }
        if let physician = test.orderingPhysician { json["ordering_physician"] = physician }

        // Results
        json["results"] = test.results.map { item -> [String: Any] in
            var result: [String: Any] = [:]

            result["name"] = item.name
            result["value"] = item.value

            if let unit = item.unit { result["unit"] = unit }
            if let referenceRange = item.referenceRange { result["reference_range"] = referenceRange }

            result["is_abnormal"] = item.isAbnormal

            if let category = item.category {
                result["category"] = category.jsonValue
            }

            if let notes = item.notes { result["notes"] = notes }

            return result
        }

        return json
    }

    // MARK: - Medical Document Encoder

    private static func encodeDocument(_ doc: MedicalDocumentSummary) -> [String: Any] {
        var json: [String: Any] = [:]

        json["file_name"] = doc.fileName

        if let documentDate = doc.documentDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            json["document_date"] = formatter.string(from: documentDate)
        }

        json["category"] = doc.documentCategory.jsonValue

        if let provider = doc.providerName { json["provider"] = provider }

        json["priority"] = doc.contextPriority

        // Include document content - prefer sections, fall back to extractedText
        if !doc.sections.isEmpty {
            // Sections (truncated to 500 chars per section)
            json["sections"] = doc.sections.map { section -> [String: Any] in
                var s: [String: Any] = [:]

                s["type"] = section.sectionType

                // Truncate content to 500 chars at word boundary
                let content = section.content
                if content.count > 500 {
                    let truncated = String(content.prefix(500))
                    if let lastSpace = truncated.lastIndex(of: " ") {
                        s["content"] = String(content[..<lastSpace]) + "..."
                    } else {
                        s["content"] = truncated + "..."
                    }
                } else {
                    s["content"] = content
                }

                return s
            }
        } else if let extractedText = doc.extractedText, !extractedText.isEmpty {
            // Fall back to extractedText if no sections available
            // Truncate to ~4000 chars to avoid overwhelming the context
            let maxLength = 4000
            if extractedText.count > maxLength {
                let truncated = String(extractedText.prefix(maxLength))
                if let lastSpace = truncated.lastIndex(of: " ") {
                    json["content"] = String(extractedText[..<lastSpace]) + "..."
                } else {
                    json["content"] = truncated + "..."
                }
            } else {
                json["content"] = extractedText
            }
        }

        return json
    }
}
