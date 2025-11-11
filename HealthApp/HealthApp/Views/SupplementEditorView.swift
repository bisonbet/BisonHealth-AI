import SwiftUI

struct SupplementEditorView: View {
    @Binding var supplement: Supplement
    @Environment(\.dismiss) private var dismiss

    @State private var frequencyType: FrequencyType = .daily
    @State private var customFrequency: String = ""

    enum FrequencyType: Hashable {
        case daily, twiceDaily, threeTimesDaily, weekly, other
    }

    var body: some View {
        Form {
            Section("Supplement Details") {
                TextField("Supplement Name", text: $supplement.name)

                Picker("Category", selection: $supplement.category) {
                    ForEach(SupplementCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    TextField("Dosage", value: $supplement.dosage.value, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $supplement.dosage.unit) {
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

            Section("Additional Information") {
                DatePicker("Start Date", selection: Binding(
                    get: { supplement.startDate ?? Date() },
                    set: { supplement.startDate = $0.timeIntervalSince1970 > 0 ? $0 : nil }
                ), displayedComponents: .date)

                TextField("Notes", text: Binding(get: { supplement.notes ?? "" }, set: { supplement.notes = $0 }), axis: .vertical)
                    .lineLimit(3...6)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(supplement.name.isEmpty ? "New Supplement" : "Edit Supplement")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setupView)
        .onDisappear(perform: saveChanges)
    }

    private func setupView() {
        // Setup frequency
        switch supplement.frequency {
        case .daily: frequencyType = .daily
        case .twiceDaily: frequencyType = .twiceDaily
        case .threeTimesDaily: frequencyType = .threeTimesDaily
        case .weekly: frequencyType = .weekly
        case .other(let custom):
            frequencyType = .other
            customFrequency = custom
        }
    }

    private func saveChanges() {
        // Save frequency
        switch frequencyType {
        case .daily: supplement.frequency = .daily
        case .twiceDaily: supplement.frequency = .twiceDaily
        case .threeTimesDaily: supplement.frequency = .threeTimesDaily
        case .weekly: supplement.frequency = .weekly
        case .other: supplement.frequency = .other(customFrequency)
        }
    }
}

#Preview {
    NavigationStack {
        SupplementEditorView(supplement: .constant(Supplement(name: "Vitamin D3", category: .vitamin)))
    }
}
