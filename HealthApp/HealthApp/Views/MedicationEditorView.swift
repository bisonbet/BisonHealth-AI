import SwiftUI

struct MedicationEditorView: View {
    @Binding var medication: Medication
    @Environment(\.dismiss) private var dismiss
    
    @State private var frequencyType: FrequencyType = .daily
    @State private var customFrequency: String = ""
    @State private var endDateType: EndDateType = .ongoing
    @State private var specificEndDate: Date = Date()

    enum FrequencyType: Hashable {
        case daily, twiceDaily, threeTimesDaily, weekly, other
    }

    enum EndDateType: Hashable {
        case ongoing, specific
    }
    
    var body: some View {
        Form {
            Section("Medication Details") {
                TextField("Medication Name", text: $medication.name)
                
                HStack {
                    TextField("Dosage", value: $medication.dosage.value, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $medication.dosage.unit) {
                        ForEach(DosageUnit.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            Section("Frequency") {
                Picker("Frequency", selection: $frequencyType) {
                    Text("Daily").tag(FrequencyType.daily)
                    Text("Twice a day").tag(FrequencyType.twiceDaily)
                    Text("Three times a day").tag(FrequencyType.threeTimesDaily)
                    Text("Weekly").tag(FrequencyType.weekly)
                    Text("Other").tag(FrequencyType.other)
                }
                .pickerStyle(.menu)
                
                if frequencyType == .other {
                    TextField("Custom Frequency", text: $customFrequency)
                }
            }
            
            Section("Duration") {
                Picker("End Date", selection: $endDateType) {
                    Text("Ongoing").tag(EndDateType.ongoing)
                    Text("Specific End Date").tag(EndDateType.specific)
                }
                .pickerStyle(.segmented)

                if endDateType == .specific {
                    DatePicker("End Date", selection: $specificEndDate, displayedComponents: .date)
                }
            }

            Section("Additional Information") {
                TextField("Prescribed By", text: Binding(get: { medication.prescribedBy ?? "" }, set: { medication.prescribedBy = $0 }))
                    .autocorrectionDisabled()

                DatePicker("Start Date", selection: Binding(
                    get: { medication.startDate ?? Date() },
                    set: { medication.startDate = $0.timeIntervalSince1970 > 0 ? $0 : nil }
                ), displayedComponents: .date)

                TextField("Notes", text: Binding(get: { medication.notes ?? "" }, set: { medication.notes = $0 }))
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(medication.name.isEmpty ? "New Medication" : "Edit Medication")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setupView)
        .onDisappear(perform: saveChanges)
    }
    
    private func setupView() {
        // Setup frequency
        switch medication.frequency {
        case .daily: frequencyType = .daily
        case .twiceDaily: frequencyType = .twiceDaily
        case .threeTimesDaily: frequencyType = .threeTimesDaily
        case .weekly: frequencyType = .weekly
        case .other(let custom):
            frequencyType = .other
            customFrequency = custom
        }

        // Setup end date
        switch medication.endDate {
        case .none, .ongoing:
            endDateType = .ongoing
        case .specific(let date):
            endDateType = .specific
            specificEndDate = date
        }
    }

    private func saveChanges() {
        // Save frequency
        switch frequencyType {
        case .daily: medication.frequency = .daily
        case .twiceDaily: medication.frequency = .twiceDaily
        case .threeTimesDaily: medication.frequency = .threeTimesDaily
        case .weekly: medication.frequency = .weekly
        case .other: medication.frequency = .other(customFrequency)
        }

        // Save end date
        switch endDateType {
        case .ongoing:
            medication.endDate = .ongoing
        case .specific:
            medication.endDate = .specific(specificEndDate)
        }
    }
}

#Preview {
    NavigationStack {
        MedicationEditorView(medication: .constant(Medication(name: "Test")))
    }
}
