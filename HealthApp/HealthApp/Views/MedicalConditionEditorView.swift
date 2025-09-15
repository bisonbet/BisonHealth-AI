import SwiftUI

struct MedicalConditionEditorView: View {
    @Binding var condition: MedicalCondition
    @Environment(\.dismiss) private var dismiss

    @State private var hasDiagnosedDate: Bool = false

    var body: some View {
        Form {
            Section("Condition Details") {
                TextField("Condition Name", text: $condition.name)
                    .autocorrectionDisabled()

                Picker("Status", selection: $condition.status) {
                    ForEach(MedicalConditionStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.menu)

                Picker("Severity", selection: $condition.severity) {
                    Text("Not specified").tag(nil as MedicalConditionSeverity?)
                    ForEach(MedicalConditionSeverity.allCases, id: \.self) { severity in
                        Text(severity.displayName).tag(severity as MedicalConditionSeverity?)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Diagnosis Information") {
                Toggle("Has Diagnosis Date", isOn: $hasDiagnosedDate)

                if hasDiagnosedDate {
                    DatePicker("Diagnosed Date", selection: Binding(
                        get: { condition.diagnosedDate ?? Date() },
                        set: { condition.diagnosedDate = $0 }
                    ), displayedComponents: .date)
                }
            }

            Section("Additional Information") {
                TextField("Treating Physician", text: Binding(
                    get: { condition.treatingPhysician ?? "" },
                    set: { condition.treatingPhysician = $0.isEmpty ? nil : $0 }
                ))
                .autocorrectionDisabled()

                TextField("Notes", text: Binding(
                    get: { condition.notes ?? "" },
                    set: { condition.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
                .autocorrectionDisabled()
            }
        }
        .navigationTitle(condition.name.isEmpty ? "New Condition" : "Edit Condition")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setupView)
        .onDisappear(perform: saveChanges)
    }

    private func setupView() {
        hasDiagnosedDate = condition.diagnosedDate != nil
    }

    private func saveChanges() {
        if !hasDiagnosedDate {
            condition.diagnosedDate = nil
        }
    }
}

#Preview {
    NavigationStack {
        MedicalConditionEditorView(condition: .constant(MedicalCondition(name: "Test Condition")))
    }
}