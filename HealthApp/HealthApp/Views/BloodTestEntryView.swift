import SwiftUI

struct BloodTestEntryView: View {
    let onSave: (BloodTestResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var testDate = Date()
    @State private var laboratoryName = ""
    @State private var orderingPhysician = ""
    @State private var results: [BloodTestItem] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Test Information") {
                    DatePicker("Test Date", selection: $testDate, displayedComponents: .date)
                    
                    TextField("Laboratory Name", text: $laboratoryName)
                    
                    TextField("Ordering Physician", text: $orderingPhysician)
                }
                
                Section("Test Results") {
                    ForEach(results) { result in
                        BloodTestItemEditor(item: Binding(
                            get: { result },
                            set: { newValue in
                                if let index = results.firstIndex(where: { $0.id == result.id }) {
                                    results[index] = newValue
                                }
                            }
                        ))
                    }
                    .onDelete { indexSet in
                        results.remove(atOffsets: indexSet)
                    }
                    
                    Button("Add Test Result") {
                        results.append(BloodTestItem(name: "", value: ""))
                    }
                }
                
                if results.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "testtube.2")
                                .font(.title)
                                .foregroundColor(.secondary)
                            
                            Text("No test results added")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Add individual test results to create a complete blood test record")
                                .font(.caption)
                                .foregroundColor(Color(.tertiaryLabel))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Blood Test Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let bloodTest = BloodTestResult(
                            testDate: testDate,
                            laboratoryName: laboratoryName.isEmpty ? nil : laboratoryName,
                            orderingPhysician: orderingPhysician.isEmpty ? nil : orderingPhysician,
                            results: results.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        )
                        onSave(bloodTest)
                        dismiss()
                    }
                    .disabled(results.isEmpty || results.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
        }
    }
}

struct BloodTestItemEditor: View {
    @Binding var item: BloodTestItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Test Name (e.g., Glucose, Cholesterol)", text: $item.name)
                .font(.headline)
            
            HStack {
                TextField("Value", text: $item.value)
                    .keyboardType(.decimalPad)
                
                TextField("Unit", text: Binding(
                    get: { item.unit ?? "" },
                    set: { item.unit = $0.isEmpty ? nil : $0 }
                ))
                .frame(maxWidth: 80)
            }
            
            TextField("Reference Range (optional)", text: Binding(
                get: { item.referenceRange ?? "" },
                set: { item.referenceRange = $0.isEmpty ? nil : $0 }
            ))
            .font(.caption)
            
            Toggle("Abnormal Result", isOn: $item.isAbnormal)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BloodTestEntryView { bloodTest in
        print("Saved blood test with \(bloodTest.results.count) results")
    }
}