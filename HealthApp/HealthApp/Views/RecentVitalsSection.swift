import SwiftUI

// MARK: - Recent Vitals Section
struct RecentVitalsSection: View {
    let personalInfo: PersonalHealthInfo?
    let onAddVital: (VitalType) -> Void
    let onEditVital: (VitalType, Int) -> Void
    let onDeleteVital: (VitalType, Int) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Section {
            if let info = personalInfo, hasVitalsOrSleep(info) {
                VStack(spacing: 16) {
                    // Blood Pressure
                    if !info.bloodPressureReadings.isEmpty {
                        VitalCategoryView(
                            title: "Blood Pressure",
                            icon: "heart.fill",
                            color: .red,
                            onAdd: { onAddVital(.bloodPressure) }
                        ) {
                            ForEach(Array(info.bloodPressureReadings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                                BloodPressureReadingRow(
                                    reading: reading,
                                    onEdit: { onEditVital(.bloodPressure, index) },
                                    onDelete: { onDeleteVital(.bloodPressure, index) }
                                )
                            }
                        }
                    }

                    // Heart Rate
                    if !info.heartRateReadings.isEmpty {
                        VitalCategoryView(
                            title: "Heart Rate",
                            icon: "waveform.path.ecg",
                            color: .pink,
                            onAdd: { onAddVital(.heartRate) }
                        ) {
                            ForEach(Array(info.heartRateReadings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                                VitalReadingRow(
                                    reading: reading,
                                    onEdit: { onEditVital(.heartRate, index) },
                                    onDelete: { onDeleteVital(.heartRate, index) }
                                )
                            }
                        }
                    }

                    // Weight
                    if !info.weightReadings.isEmpty {
                        VitalCategoryView(
                            title: "Weight",
                            icon: "scalemass",
                            color: .blue,
                            onAdd: { onAddVital(.weight) }
                        ) {
                            ForEach(Array(info.weightReadings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                                VitalReadingRow(
                                    reading: reading,
                                    onEdit: { onEditVital(.weight, index) },
                                    onDelete: { onDeleteVital(.weight, index) }
                                )
                            }
                        }
                    }

                    // Body Temperature
                    if !info.bodyTemperatureReadings.isEmpty {
                        VitalCategoryView(
                            title: "Body Temperature",
                            icon: "thermometer",
                            color: .orange,
                            onAdd: { onAddVital(.bodyTemperature) }
                        ) {
                            ForEach(Array(info.bodyTemperatureReadings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                                VitalReadingRow(
                                    reading: reading,
                                    onEdit: { onEditVital(.bodyTemperature, index) },
                                    onDelete: { onDeleteVital(.bodyTemperature, index) }
                                )
                            }
                        }
                    }

                    // Oxygen Saturation
                    if !info.oxygenSaturationReadings.isEmpty {
                        VitalCategoryView(
                            title: "Oxygen Saturation",
                            icon: "lungs.fill",
                            color: .cyan,
                            onAdd: { onAddVital(.oxygenSaturation) }
                        ) {
                            ForEach(Array(info.oxygenSaturationReadings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                                VitalReadingRow(
                                    reading: reading,
                                    onEdit: { onEditVital(.oxygenSaturation, index) },
                                    onDelete: { onDeleteVital(.oxygenSaturation, index) }
                                )
                            }
                        }
                    }

                    // Respiratory Rate
                    if !info.respiratoryRateReadings.isEmpty {
                        VitalCategoryView(
                            title: "Respiratory Rate",
                            icon: "wind",
                            color: .teal,
                            onAdd: { onAddVital(.respiratoryRate) }
                        ) {
                            ForEach(Array(info.respiratoryRateReadings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                                VitalReadingRow(
                                    reading: reading,
                                    onEdit: { onEditVital(.respiratoryRate, index) },
                                    onDelete: { onDeleteVital(.respiratoryRate, index) }
                                )
                            }
                        }
                    }

                    // Sleep Data
                    if !info.sleepData.isEmpty {
                        VitalCategoryView(
                            title: "Sleep",
                            icon: "moon.fill",
                            color: .indigo,
                            onAdd: { onAddVital(.sleep) }
                        ) {
                            ForEach(Array(info.sleepData.prefix(7).enumerated()), id: \.element.id) { index, sleep in
                                SleepDataRow(
                                    sleep: sleep,
                                    onEdit: { onEditVital(.sleep, index) },
                                    onDelete: { onDeleteVital(.sleep, index) }
                                )
                            }
                        }
                    }
                }
            } else {
                EmptyVitalsView()
            }
        } header: {
            Label("Recent Vitals", systemImage: "heart.text.square")
        }
    }

    private func hasVitalsOrSleep(_ info: PersonalHealthInfo) -> Bool {
        !info.bloodPressureReadings.isEmpty ||
        !info.heartRateReadings.isEmpty ||
        !info.bodyTemperatureReadings.isEmpty ||
        !info.oxygenSaturationReadings.isEmpty ||
        !info.respiratoryRateReadings.isEmpty ||
        !info.weightReadings.isEmpty ||
        !info.sleepData.isEmpty
    }
}

// MARK: - Vital Category View
struct VitalCategoryView<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let onAdd: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(color)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                content
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vital Reading Row
struct VitalReadingRow: View {
    let reading: VitalReading
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showingActions = false

    var body: some View {
        HStack(spacing: 12) {
            // Value and timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.displayValue)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(formattedDate(reading.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(reading.source.displayName)
                        .font(.caption)
                        .foregroundColor(reading.source == .appleHealth ? .blue : .green)
                }
            }

            Spacer()

            // Actions button
            Menu {
                Button("Edit", systemImage: "pencil") {
                    onEdit()
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Blood Pressure Reading Row
struct BloodPressureReadingRow: View {
    let reading: VitalReading
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Value and timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.displayValue)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(formattedDate(reading.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(reading.source.displayName)
                        .font(.caption)
                        .foregroundColor(reading.source == .appleHealth ? .blue : .green)
                }
            }

            Spacer()

            // Actions button
            Menu {
                Button("Edit", systemImage: "pencil") {
                    onEdit()
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Sleep Data Row
struct SleepDataRow: View {
    let sleep: SleepData
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Value and timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(sleep.displayDuration)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(formattedDate(sleep.date))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let stages = sleepStagesText {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(stages)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(sleep.source.displayName)
                        .font(.caption)
                        .foregroundColor(sleep.source == .appleHealth ? .blue : .green)
                }
            }

            Spacer()

            // Actions button
            Menu {
                Button("Edit", systemImage: "pencil") {
                    onEdit()
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private var sleepStagesText: String? {
        var stages: [String] = []
        if let deep = sleep.deepSleepMinutes {
            stages.append("Deep: \(deep)m")
        }
        if let rem = sleep.remSleepMinutes {
            stages.append("REM: \(rem)m")
        }
        return stages.isEmpty ? nil : stages.joined(separator: ", ")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Empty Vitals View
struct EmptyVitalsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No vitals data yet")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Sync with Apple Health or add manually")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Vital Type Enum
enum VitalType {
    case bloodPressure
    case heartRate
    case weight
    case bodyTemperature
    case oxygenSaturation
    case respiratoryRate
    case sleep
}
