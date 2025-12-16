import SwiftUI

// MARK: - Vitals List View
struct VitalsListView: View {
    @StateObject private var healthDataManager = HealthDataManager.shared
    @State private var showingVitalEntry: VitalType?
    @State private var editingVital: (type: VitalType, index: Int)?

    var body: some View {
        List {
            RecentVitalsSection(
                personalInfo: healthDataManager.personalInfo,
                onAddVital: { vitalType in
                    HapticFeedbackManager.shared.impact()
                    showingVitalEntry = vitalType
                },
                onEditVital: { vitalType, index in
                    HapticFeedbackManager.shared.impact()
                    editingVital = (vitalType, index)
                },
                onDeleteVital: { vitalType, index in
                    HapticFeedbackManager.shared.impact()
                    Task {
                        await deleteVitalReading(type: vitalType, index: index)
                    }
                }
            )
        }
        .navigationTitle("Recent Vitals")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $showingVitalEntry) { vitalType in
            VitalEntryView(
                vitalType: vitalType,
                existingReading: nil,
                personalInfo: healthDataManager.personalInfo,
                onSave: { updatedInfo in
                    HapticFeedbackManager.shared.success()
                    Task {
                        try await healthDataManager.savePersonalInfo(updatedInfo)
                    }
                }
            )
        }
        .sheet(item: Binding(
            get: { editingVital.map { EditingVitalWrapper(type: $0.type, index: $0.index) } },
            set: { editingVital = $0.map { ($0.type, $0.index) } }
        )) { wrapper in
            VitalEntryView(
                vitalType: wrapper.type,
                existingReading: (wrapper.type, wrapper.index),
                personalInfo: healthDataManager.personalInfo,
                onSave: { updatedInfo in
                    HapticFeedbackManager.shared.success()
                    Task {
                        try await healthDataManager.savePersonalInfo(updatedInfo)
                    }
                }
            )
        }
    }

    // MARK: - Vital Management Helpers
    private func deleteVitalReading(type: VitalType, index: Int) async {
        guard var info = healthDataManager.personalInfo else { return }

        switch type {
        case .bloodPressure:
            if index < info.bloodPressureReadings.count {
                info.bloodPressureReadings.remove(at: index)
            }
        case .heartRate:
            if index < info.heartRateReadings.count {
                info.heartRateReadings.remove(at: index)
            }
        case .weight:
            if index < info.weightReadings.count {
                info.weightReadings.remove(at: index)
            }
        case .bodyTemperature:
            if index < info.bodyTemperatureReadings.count {
                info.bodyTemperatureReadings.remove(at: index)
            }
        case .oxygenSaturation:
            if index < info.oxygenSaturationReadings.count {
                info.oxygenSaturationReadings.remove(at: index)
            }
        case .respiratoryRate:
            if index < info.respiratoryRateReadings.count {
                info.respiratoryRateReadings.remove(at: index)
            }
        case .sleep:
            if index < info.sleepData.count {
                info.sleepData.remove(at: index)
            }
        }

        do {
            try await healthDataManager.savePersonalInfo(info)
        } catch {
            print("Failed to delete vital reading: \(error)")
        }
    }
}
