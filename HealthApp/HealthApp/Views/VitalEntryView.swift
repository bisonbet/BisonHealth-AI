import SwiftUI

// MARK: - Vital Entry View
struct VitalEntryView: View {
    let vitalType: VitalType
    let existingReading: (type: VitalType, index: Int)?
    let personalInfo: PersonalHealthInfo?
    let onSave: (PersonalHealthInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    // State for different vital types
    @State private var systolic: String = ""
    @State private var diastolic: String = ""
    @State private var value: String = ""
    @State private var selectedDate: Date = Date()
    @State private var source: VitalSource = .manual

    // Sleep-specific
    @State private var sleepStart: Date = Date()
    @State private var sleepEnd: Date = Date()
    @State private var deepSleep: String = ""
    @State private var remSleep: String = ""
    @State private var coreSleep: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch vitalType {
                    case .bloodPressure:
                        bloodPressureFields
                    case .heartRate:
                        heartRateFields
                    case .weight:
                        weightFields
                    case .bodyTemperature:
                        temperatureFields
                    case .oxygenSaturation:
                        oxygenSaturationFields
                    case .respiratoryRate:
                        respiratoryRateFields
                    case .sleep:
                        sleepFields
                    }

                    DatePicker("Date", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])

                    Picker("Source", selection: $source) {
                        Text("Manual").tag(VitalSource.manual)
                        Text("Apple Health").tag(VitalSource.appleHealth)
                    }
                } header: {
                    Text(vitalType.displayName)
                }
            }
            .navigationTitle(existingReading != nil ? "Edit \(vitalType.displayName)" : "Add \(vitalType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveReading()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadExistingReading()
            }
        }
    }

    // MARK: - Field Views

    private var bloodPressureFields: some View {
        Group {
            TextField("Systolic (mmHg)", text: $systolic)
                .keyboardType(.numberPad)

            TextField("Diastolic (mmHg)", text: $diastolic)
                .keyboardType(.numberPad)
        }
    }

    private var heartRateFields: some View {
        TextField("Heart Rate (bpm)", text: $value)
            .keyboardType(.numberPad)
    }

    private var weightFields: some View {
        TextField("Weight (lbs)", text: $value)
            .keyboardType(.decimalPad)
    }

    private var temperatureFields: some View {
        TextField("Temperature (°F)", text: $value)
            .keyboardType(.decimalPad)
    }

    private var oxygenSaturationFields: some View {
        TextField("Oxygen Saturation (%)", text: $value)
            .keyboardType(.numberPad)
    }

    private var respiratoryRateFields: some View {
        TextField("Respiratory Rate (breaths/min)", text: $value)
            .keyboardType(.numberPad)
    }

    private var sleepFields: some View {
        Group {
            DatePicker("Sleep Start", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])

            DatePicker("Sleep End", selection: $sleepEnd, displayedComponents: [.date, .hourAndMinute])

            TextField("Deep Sleep (minutes, optional)", text: $deepSleep)
                .keyboardType(.numberPad)

            TextField("REM Sleep (minutes, optional)", text: $remSleep)
                .keyboardType(.numberPad)

            TextField("Core Sleep (minutes, optional)", text: $coreSleep)
                .keyboardType(.numberPad)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        switch vitalType {
        case .bloodPressure:
            return !systolic.isEmpty && !diastolic.isEmpty &&
                   Int(systolic) != nil && Int(diastolic) != nil
        case .heartRate, .oxygenSaturation, .respiratoryRate:
            return !value.isEmpty && Double(value) != nil
        case .weight, .bodyTemperature:
            return !value.isEmpty && Double(value) != nil
        case .sleep:
            return sleepEnd > sleepStart
        }
    }

    // MARK: - Load Existing Reading

    private func loadExistingReading() {
        guard let existing = existingReading,
              let info = personalInfo else { return }

        switch existing.type {
        case .bloodPressure:
            if existing.index < info.bloodPressureReadings.count {
                let reading = info.bloodPressureReadings[existing.index]
                if let sys = reading.systolic, let dia = reading.diastolic {
                    systolic = String(Int(sys))
                    diastolic = String(Int(dia))
                }
                selectedDate = reading.timestamp
                source = reading.source
            }
        case .heartRate:
            if existing.index < info.heartRateReadings.count {
                let reading = info.heartRateReadings[existing.index]
                value = String(Int(reading.value))
                selectedDate = reading.timestamp
                source = reading.source
            }
        case .weight:
            if existing.index < info.weightReadings.count {
                let reading = info.weightReadings[existing.index]
                value = String(format: "%.1f", reading.value)
                selectedDate = reading.timestamp
                source = reading.source
            }
        case .bodyTemperature:
            if existing.index < info.bodyTemperatureReadings.count {
                let reading = info.bodyTemperatureReadings[existing.index]
                value = String(format: "%.1f", reading.value)
                selectedDate = reading.timestamp
                source = reading.source
            }
        case .oxygenSaturation:
            if existing.index < info.oxygenSaturationReadings.count {
                let reading = info.oxygenSaturationReadings[existing.index]
                value = String(Int(reading.value))
                selectedDate = reading.timestamp
                source = reading.source
            }
        case .respiratoryRate:
            if existing.index < info.respiratoryRateReadings.count {
                let reading = info.respiratoryRateReadings[existing.index]
                value = String(Int(reading.value))
                selectedDate = reading.timestamp
                source = reading.source
            }
        case .sleep:
            if existing.index < info.sleepData.count {
                let sleep = info.sleepData[existing.index]
                sleepStart = sleep.startTime
                sleepEnd = sleep.endTime
                selectedDate = sleep.date
                source = sleep.source
                if let deep = sleep.deepSleepMinutes {
                    deepSleep = String(deep)
                }
                if let rem = sleep.remSleepMinutes {
                    remSleep = String(rem)
                }
                if let core = sleep.coreSleepMinutes {
                    coreSleep = String(core)
                }
            }
        }
    }

    // MARK: - Save Reading

    private func saveReading() {
        var info = personalInfo ?? PersonalHealthInfo()

        switch vitalType {
        case .bloodPressure:
            guard let sys = Int(systolic), let dia = Int(diastolic) else { return }
            let reading = VitalReading(
                value: Double(sys), // Store systolic as primary value
                unit: "mmHg",
                timestamp: selectedDate,
                source: source,
                systolic: Double(sys),
                diastolic: Double(dia)
            )

            if let existing = existingReading, existing.index < info.bloodPressureReadings.count {
                info.bloodPressureReadings[existing.index] = reading
            } else {
                info.bloodPressureReadings.insert(reading, at: 0)
                info.bloodPressureReadings.sort { $0.timestamp > $1.timestamp }
            }

        case .heartRate:
            guard let val = Double(value) else { return }
            let reading = VitalReading(value: val, unit: "bpm", timestamp: selectedDate, source: source)

            if let existing = existingReading, existing.index < info.heartRateReadings.count {
                info.heartRateReadings[existing.index] = reading
            } else {
                info.heartRateReadings.insert(reading, at: 0)
                info.heartRateReadings.sort { $0.timestamp > $1.timestamp }
            }

        case .weight:
            guard let val = Double(value) else { return }
            let reading = VitalReading(value: val, unit: "lbs", timestamp: selectedDate, source: source)

            if let existing = existingReading, existing.index < info.weightReadings.count {
                info.weightReadings[existing.index] = reading
            } else {
                info.weightReadings.insert(reading, at: 0)
                info.weightReadings.sort { $0.timestamp > $1.timestamp }
            }

            // Update main weight property
            let weightInPounds = Measurement(value: val, unit: UnitMass.pounds)
            info.weight = weightInPounds.converted(to: .kilograms)

        case .bodyTemperature:
            guard let val = Double(value) else { return }
            let reading = VitalReading(value: val, unit: "°F", timestamp: selectedDate, source: source)

            if let existing = existingReading, existing.index < info.bodyTemperatureReadings.count {
                info.bodyTemperatureReadings[existing.index] = reading
            } else {
                info.bodyTemperatureReadings.insert(reading, at: 0)
                info.bodyTemperatureReadings.sort { $0.timestamp > $1.timestamp }
            }

        case .oxygenSaturation:
            guard let val = Double(value) else { return }
            let reading = VitalReading(value: val, unit: "%", timestamp: selectedDate, source: source)

            if let existing = existingReading, existing.index < info.oxygenSaturationReadings.count {
                info.oxygenSaturationReadings[existing.index] = reading
            } else {
                info.oxygenSaturationReadings.insert(reading, at: 0)
                info.oxygenSaturationReadings.sort { $0.timestamp > $1.timestamp }
            }

        case .respiratoryRate:
            guard let val = Double(value) else { return }
            let reading = VitalReading(value: val, unit: "breaths/min", timestamp: selectedDate, source: source)

            if let existing = existingReading, existing.index < info.respiratoryRateReadings.count {
                info.respiratoryRateReadings[existing.index] = reading
            } else {
                info.respiratoryRateReadings.insert(reading, at: 0)
                info.respiratoryRateReadings.sort { $0.timestamp > $1.timestamp }
            }

        case .sleep:
            let totalMinutes = Int(sleepEnd.timeIntervalSince(sleepStart) / 60)
            let sleep = SleepData(
                date: selectedDate,
                startTime: sleepStart,
                endTime: sleepEnd,
                totalSleepMinutes: totalMinutes,
                source: source,
                deepSleepMinutes: deepSleep.isEmpty ? nil : Int(deepSleep),
                remSleepMinutes: remSleep.isEmpty ? nil : Int(remSleep),
                coreSleepMinutes: coreSleep.isEmpty ? nil : Int(coreSleep),
                awakeMinutes: nil,
                inBedMinutes: nil
            )

            if let existing = existingReading, existing.index < info.sleepData.count {
                info.sleepData[existing.index] = sleep
            } else {
                info.sleepData.insert(sleep, at: 0)
                info.sleepData.sort { $0.date > $1.date }
            }
        }

        onSave(info)
    }
}

// MARK: - VitalType Extension
extension VitalType {
    var displayName: String {
        switch self {
        case .bloodPressure: return "Blood Pressure"
        case .heartRate: return "Heart Rate"
        case .weight: return "Weight"
        case .bodyTemperature: return "Body Temperature"
        case .oxygenSaturation: return "Oxygen Saturation"
        case .respiratoryRate: return "Respiratory Rate"
        case .sleep: return "Sleep"
        }
    }
}
