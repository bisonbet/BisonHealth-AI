import SwiftUI

struct BloodTestEntryView: View {
    let onSave: (BloodTestResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var testDate = Date()
    @State private var laboratoryName = ""
    @State private var orderingPhysician = ""
    @State private var results: [BloodTestItem] = []
    
    // Validation states
    @State private var testDateValidationError: String?
    @State private var resultsValidationError: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Test Information") {
                    VStack(alignment: .leading) {
                        DatePicker("Test Date", selection: Binding(
                            get: { testDate },
                            set: { newValue in
                                testDate = newValue
                                validateTestDate(newValue)
                            }
                        ), in: Date.distantPast...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("bloodTest.testDatePicker")
                        
                        if let error = testDateValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityIdentifier("bloodTest.testDateError")
                        }
                    }
                    
                    TextField("Laboratory Name", text: $laboratoryName)
                        .accessibilityIdentifier("bloodTest.laboratoryField")
                    
                    TextField("Ordering Physician", text: $orderingPhysician)
                        .accessibilityIdentifier("bloodTest.physicianField")
                }
                
                Section("Test Results") {
                    ForEach(results) { result in
                        BloodTestItemEditor(item: Binding(
                            get: { result },
                            set: { newValue in
                                if let index = results.firstIndex(where: { $0.id == result.id }) {
                                    results[index] = newValue
                                    validateResults()
                                }
                            }
                        ))
                    }
                    .onDelete { indexSet in
                        results.remove(atOffsets: indexSet)
                        validateResults()
                    }
                    
                    Button("Add Test Result") {
                        results.append(BloodTestItem(name: "", value: ""))
                        validateResults()
                    }
                    .accessibilityIdentifier("bloodTest.addResultButton")
                    
                    if let error = resultsValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("bloodTest.resultsError")
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
                    .disabled(!isFormValid)
                    .accessibilityIdentifier("bloodTest.saveButton")
                }
            }
        }
        .onAppear {
            validateTestDate(testDate)
            validateResults()
        }
    }
    
    // MARK: - Validation Functions
    
    private func validateTestDate(_ date: Date) {
        testDateValidationError = nil
        
        let now = Date()
        if date > now {
            testDateValidationError = "Test date cannot be in the future"
        }
        
        // Check if date is more than 10 years ago (reasonable limit)
        let tenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: now) ?? Date.distantPast
        if date < tenYearsAgo {
            testDateValidationError = "Test date seems too old. Please verify the date."
        }
    }
    
    private func validateResults() {
        resultsValidationError = nil
        
        let validResults = results.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        if validResults.isEmpty {
            resultsValidationError = "At least one test result is required"
            return
        }
        
        // Check for duplicate test names
        let testNames = validResults.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let uniqueNames = Set(testNames)
        if testNames.count != uniqueNames.count {
            resultsValidationError = "Duplicate test names are not allowed"
            return
        }
        
        // Validate individual results
        for result in validResults {
            if result.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resultsValidationError = "All test results must have values"
                return
            }
        }
    }
    
    private var isFormValid: Bool {
        return testDateValidationError == nil &&
               resultsValidationError == nil &&
               !results.filter({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).isEmpty
    }
}

struct BloodTestItemEditor: View {
    @Binding var item: BloodTestItem
    @State private var nameValidationError: String?
    @State private var valueValidationError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading) {
                TextField("Test Name (e.g., Glucose, Cholesterol)", text: Binding(
                    get: { item.name },
                    set: { newValue in
                        item.name = newValue
                        validateName(newValue)
                    }
                ))
                .font(.headline)
                .accessibilityIdentifier("bloodTestItem.nameField")
                
                if let error = nameValidationError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    TextField("Value", text: Binding(
                        get: { item.value },
                        set: { newValue in
                            item.value = newValue
                            validateValue(newValue)
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("bloodTestItem.valueField")
                    
                    if let error = valueValidationError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                
                TextField("Unit", text: Binding(
                    get: { item.unit ?? "" },
                    set: { item.unit = $0.isEmpty ? nil : $0 }
                ))
                .frame(maxWidth: 80)
                .accessibilityIdentifier("bloodTestItem.unitField")
            }
            
            TextField("Reference Range (optional)", text: Binding(
                get: { item.referenceRange ?? "" },
                set: { item.referenceRange = $0.isEmpty ? nil : $0 }
            ))
            .font(.caption)
            .accessibilityIdentifier("bloodTestItem.referenceRangeField")
            
            Toggle("Abnormal Result", isOn: $item.isAbnormal)
                .font(.caption)
                .accessibilityIdentifier("bloodTestItem.abnormalToggle")
        }
        .padding(.vertical, 4)
        .onAppear {
            validateName(item.name)
            validateValue(item.value)
        }
    }
    
    private func validateName(_ name: String) {
        nameValidationError = nil
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            nameValidationError = "Test name is required"
        } else if trimmedName.count > 50 {
            nameValidationError = "Test name must be less than 50 characters"
        }
    }
    
    private func validateValue(_ value: String) {
        valueValidationError = nil
        
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedValue.isEmpty {
            valueValidationError = "Test value is required"
        } else if trimmedValue.count > 20 {
            valueValidationError = "Value must be less than 20 characters"
        }
    }
}

#Preview {
    BloodTestEntryView { bloodTest in
        print("Saved blood test with \(bloodTest.results.count) results")
    }
}