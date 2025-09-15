import SwiftUI

struct BloodTestEntryView: View {
    let bloodTest: BloodTestResult?
    let onSave: (BloodTestResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var testDate = Date()
    @State private var laboratoryName = ""
    @State private var orderingPhysician = ""
    @State private var results: [BloodTestItem] = []

    @StateObject private var dataManager = BloodTestDataManager.shared

    // Validation states
    @State private var testDateValidationError: String?
    @State private var resultsValidationError: String?

    // Focus state for keyboard management
    @FocusState private var isAnyFieldFocused: Bool

    init(bloodTest: BloodTestResult? = nil, onSave: @escaping (BloodTestResult) -> Void) {
        self.bloodTest = bloodTest
        self.onSave = onSave
        _testDate = State(initialValue: bloodTest?.testDate ?? Date())
        _laboratoryName = State(initialValue: bloodTest?.laboratoryName ?? "")
        _orderingPhysician = State(initialValue: bloodTest?.orderingPhysician ?? "")
        _results = State(initialValue: bloodTest?.results ?? [])
    }

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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Laboratory Name")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SearchableDropdownWithAddNew(
                            title: "Laboratory Name",
                            items: dataManager.getAllLaboratories(),
                            selectedValue: $laboratoryName,
                            onAddNew: { name in
                                dataManager.addLaboratory(name)
                            }
                        )
                        .accessibilityIdentifier("bloodTest.laboratoryDropdown")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ordering Physician")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SearchableDropdownWithAddNew(
                            title: "Ordering Physician",
                            items: dataManager.getAllPhysicians(),
                            selectedValue: $orderingPhysician,
                            onAddNew: { name in
                                dataManager.addPhysician(name)
                            }
                        )
                        .accessibilityIdentifier("bloodTest.physicianDropdown")
                    }
                }

                Section("Test Results") {
                    ForEach(results) { result in
                        BloodTestItemEditor(
                            item: Binding(
                                get: { result },
                                set: { newValue in
                                    if let index = results.firstIndex(where: { $0.id == result.id }) {
                                        results[index] = newValue
                                        validateResults()
                                    }
                                }
                            ),
                            isAnyFieldFocused: $isAnyFieldFocused
                        )
                    }
                    .onDelete { indexSet in
                        results.remove(atOffsets: indexSet)
                        validateResults()
                    }

                    Button("Add Test Result") {
                        results.append(BloodTestItem(name: "", value: ""))
                        validateResults()
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
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
            .navigationTitle(bloodTest == nil ? "Blood Test Entry" : "Edit Blood Test")
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
                            id: bloodTest?.id ?? UUID(),
                            testDate: testDate,
                            laboratoryName: laboratoryName.isEmpty ? nil : laboratoryName,
                            orderingPhysician: orderingPhysician.isEmpty ? nil : orderingPhysician,
                            results: results.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                            createdAt: bloodTest?.createdAt ?? Date(),
                            updatedAt: Date()
                        )
                        onSave(bloodTest)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .accessibilityIdentifier("bloodTest.saveButton")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isAnyFieldFocused = false
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
    @FocusState.Binding var isAnyFieldFocused: Bool
    @State private var nameValidationError: String?
    @State private var valueValidationError: String?

    @State private var selectedTestType: BloodTestTypeOption?
    @State private var selectedUnit: String = ""
    @State private var isShowingTestTypePicker = false

    @StateObject private var dataManager = BloodTestDataManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Test Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    TestTypeButton(
                        selectedTest: selectedTestType,
                        customTestName: item.name,
                        isShowingPicker: $isShowingTestTypePicker
                    )
                    .accessibilityIdentifier("bloodTestItem.testTypeButton")

                    // Allow manual entry for custom test names
                    TextField("Or type custom test name", text: Binding(
                        get: { selectedTestType == nil ? item.name : "" },
                        set: { newValue in
                            if selectedTestType == nil {
                                item.name = newValue
                                validateName(newValue)
                            }
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)
                    .opacity(selectedTestType == nil ? 1.0 : 0.5)
                    .disabled(selectedTestType != nil)
                    .focused($isAnyFieldFocused)
                    .onTapGesture {
                        if selectedTestType != nil {
                            selectedTestType = nil
                            selectedUnit = ""
                            item.unit = nil
                            item.referenceRange = nil
                            item.category = nil
                        }
                    }
                }

                if let error = nameValidationError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Value")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Value", text: Binding(
                        get: { item.value },
                        set: { newValue in
                            item.value = newValue
                            validateValue(newValue)
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("bloodTestItem.valueField")
                    .focused($isAnyFieldFocused)

                    if let error = valueValidationError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    UnitDropdown(
                        selectedUnit: Binding(
                            get: { selectedUnit.isEmpty ? item.unit ?? "" : selectedUnit },
                            set: { newValue in
                                selectedUnit = newValue
                                item.unit = newValue.isEmpty ? nil : newValue
                            }
                        ),
                        testKey: selectedTestType?.key
                    )
                    .accessibilityIdentifier("bloodTestItem.unitDropdown")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reference Range (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Reference Range", text: Binding(
                    get: { item.referenceRange ?? "" },
                    set: { item.referenceRange = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("bloodTestItem.referenceRangeField")
                .focused($isAnyFieldFocused)
            }

            Toggle("Abnormal Result", isOn: $item.isAbnormal)
                .font(.subheadline)
                .accessibilityIdentifier("bloodTestItem.abnormalToggle")
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isShowingTestTypePicker) {
            TestTypePickerView(
                selectedTest: $selectedTestType,
                onTestSelected: { testType in
                    selectedTestType = testType

                    // Update the item and trigger the binding
                    var updatedItem = item
                    updatedItem.name = testType.displayName
                    updatedItem.category = testType.category

                    // Auto-fill unit and reference range if available
                    if let unit = testType.unit {
                        selectedUnit = unit
                        updatedItem.unit = unit
                    }
                    if let referenceRange = testType.referenceRange {
                        updatedItem.referenceRange = referenceRange
                    }

                    // Update the item to trigger parent validation
                    item = updatedItem

                    // Clear validation error since we have a valid test name
                    nameValidationError = nil
                }
            )
        }
        .onAppear {
            // Initialize selectedUnit with current item unit
            selectedUnit = item.unit ?? ""

            // Try to find matching test type for existing item
            if !item.name.isEmpty {
                let allTests = dataManager.getStandardizedTestTypes()
                selectedTestType = allTests.first { test in
                    test.displayName.caseInsensitiveCompare(item.name) == .orderedSame ||
                    test.key.caseInsensitiveCompare(item.name.lowercased().replacingOccurrences(of: " ", with: "_")) == .orderedSame
                }
            }

            validateName(item.name)
            validateValue(item.value)
        }
        .onChange(of: selectedTestType) { _, newValue in
            // Clear validation error when test type is selected
            if newValue != nil {
                nameValidationError = nil
            } else {
                // Revalidate when test type is cleared
                validateName(item.name)
            }
        }
    }

    private func validateName(_ name: String) {
        nameValidationError = nil

        // If a test type is selected, use the item.name instead of the parameter
        let nameToValidate = selectedTestType != nil ? item.name : name
        let trimmedName = nameToValidate.trimmingCharacters(in: .whitespacesAndNewlines)

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