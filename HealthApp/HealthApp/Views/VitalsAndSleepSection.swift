import SwiftUI

// MARK: - Vitals and Sleep Section
struct VitalsAndSleepSection: View {
    let personalInfo: PersonalHealthInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Vitals Section
            if hasAnyVitals {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRowHeader(label: "Recent Vitals", icon: "heart.text.square")

                    HStack {
                        Spacer().frame(width: 28)
                        VStack(alignment: .leading, spacing: 12) {
                            if !personalInfo.bloodPressureReadings.isEmpty {
                                VitalSummaryRow(
                                    icon: "heart.circle",
                                    label: "Blood Pressure",
                                    readings: personalInfo.bloodPressureReadings,
                                    color: .red
                                )
                            }

                            if !personalInfo.heartRateReadings.isEmpty {
                                VitalSummaryRow(
                                    icon: "waveform.path.ecg",
                                    label: "Heart Rate",
                                    readings: personalInfo.heartRateReadings,
                                    color: .pink
                                )
                            }

                            if !personalInfo.oxygenSaturationReadings.isEmpty {
                                VitalSummaryRow(
                                    icon: "o.circle",
                                    label: "Oxygen Saturation",
                                    readings: personalInfo.oxygenSaturationReadings,
                                    color: .blue
                                )
                            }

                            if !personalInfo.bodyTemperatureReadings.isEmpty {
                                VitalSummaryRow(
                                    icon: "thermometer",
                                    label: "Temperature",
                                    readings: personalInfo.bodyTemperatureReadings,
                                    color: .orange
                                )
                            }

                            if !personalInfo.respiratoryRateReadings.isEmpty {
                                VitalSummaryRow(
                                    icon: "wind",
                                    label: "Respiratory Rate",
                                    readings: personalInfo.respiratoryRateReadings,
                                    color: .teal
                                )
                            }

                            if !personalInfo.weightReadings.isEmpty {
                                VitalSummaryRow(
                                    icon: "scalemass",
                                    label: "Weight",
                                    readings: personalInfo.weightReadings,
                                    color: .purple
                                )
                            }
                        }
                    }
                }
            }

            // Sleep Data Section
            if !personalInfo.sleepData.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRowHeader(label: "Recent Sleep", icon: "bed.double.fill")

                    HStack {
                        Spacer().frame(width: 28)
                        VStack(alignment: .leading, spacing: 8) {
                            SleepSummaryRow(sleepData: personalInfo.sleepData)
                        }
                    }
                }
            }
        }
    }

    private var hasAnyVitals: Bool {
        !personalInfo.bloodPressureReadings.isEmpty ||
        !personalInfo.heartRateReadings.isEmpty ||
        !personalInfo.bodyTemperatureReadings.isEmpty ||
        !personalInfo.oxygenSaturationReadings.isEmpty ||
        !personalInfo.respiratoryRateReadings.isEmpty ||
        !personalInfo.weightReadings.isEmpty
    }
}

// MARK: - Vital Summary Row
struct VitalSummaryRow: View {
    let icon: String
    let label: String
    let readings: [VitalReading]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 16)

                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                if let latest = readings.first {
                    Text(latest.displayValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
            }

            // Show last 3 readings
            ForEach(readings.prefix(3)) { reading in
                HStack {
                    Spacer().frame(width: 16)

                    Text(DateFormatter.shortDate.string(from: reading.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(reading.displayValue)
                        .font(.caption2)

                    Image(systemName: reading.source == .appleHealth ? "applelogo" : "pencil")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Sleep Summary Row
struct SleepSummaryRow: View {
    let sleepData: [SleepData]

    var avgSleepHours: Double {
        let totalMinutes = sleepData.prefix(7).reduce(0) { $0 + $1.totalSleepMinutes }
        return Double(totalMinutes) / Double(min(sleepData.count, 7)) / 60.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(.indigo)
                    .frame(width: 16)

                Text("Average Sleep")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(String(format: "%.1f hrs", avgSleepHours))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.indigo)
            }

            // Show last 3 nights
            ForEach(sleepData.prefix(3)) { sleep in
                HStack {
                    Spacer().frame(width: 16)

                    Text(DateFormatter.shortDate.string(from: sleep.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(sleep.displayDuration)
                        .font(.caption2)

                    if let deep = sleep.deepSleepMinutes, let rem = sleep.remSleepMinutes {
                        Text("D:\(deep)m R:\(rem)m")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: sleep.source == .appleHealth ? "applelogo" : "pencil")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    List {
        Section {
            VitalsAndSleepSection(
                personalInfo: PersonalHealthInfo(
                    bloodPressureReadings: [
                        VitalReading(value: 120, unit: "mmHg", timestamp: Date(), source: .appleHealth, systolic: 120, diastolic: 80),
                        VitalReading(value: 118, unit: "mmHg", timestamp: Date().addingTimeInterval(-86400), source: .manual, systolic: 118, diastolic: 78)
                    ],
                    heartRateReadings: [
                        VitalReading(value: 72, unit: "bpm", timestamp: Date(), source: .appleHealth),
                        VitalReading(value: 75, unit: "bpm", timestamp: Date().addingTimeInterval(-86400), source: .appleHealth)
                    ],
                    sleepData: [
                        SleepData(
                            date: Date(),
                            startTime: Date().addingTimeInterval(-28800),
                            endTime: Date(),
                            totalSleepMinutes: 420,
                            source: .appleHealth,
                            deepSleepMinutes: 90,
                            remSleepMinutes: 120
                        ),
                        SleepData(
                            date: Date().addingTimeInterval(-86400),
                            startTime: Date().addingTimeInterval(-115200),
                            endTime: Date().addingTimeInterval(-86400),
                            totalSleepMinutes: 390,
                            source: .appleHealth,
                            deepSleepMinutes: 80,
                            remSleepMinutes: 110
                        )
                    ]
                )
            )
        } header: {
            Text("Health Metrics")
        }
    }
}
