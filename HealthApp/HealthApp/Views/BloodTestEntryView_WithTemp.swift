import SwiftUI

// MARK: - Temporary inline classes until we add files to project

// MARK: - Simplified Blood Test Data Manager (Inline)
class BloodTestDataManager: ObservableObject {
    static let shared = BloodTestDataManager()

    @Published var commonLaboratories: [String] = []
    @Published var commonPhysicians: [String] = []

    private init() {
        setupDefaultData()
    }

    func getAllLaboratories() -> [String] {
        return commonLaboratories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func getAllPhysicians() -> [String] {
        return commonPhysicians.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func addLaboratory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !commonLaboratories.contains(trimmed) else { return }
        commonLaboratories.append(trimmed)
    }

    func addPhysician(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !commonPhysicians.contains(trimmed) else { return }
        commonPhysicians.append(trimmed)
    }

    func getStandardizedTestTypes() -> [BloodTestTypeOption] {
        let parameters = BloodTestResult.standardizedLabParameters
        return parameters.map { (key, parameter) in
            BloodTestTypeOption(
                key: parameter.key,
                displayName: parameter.name,
                unit: parameter.unit,
                referenceRange: parameter.referenceRange,
                category: parameter.category,
                description: parameter.description
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    func getCommonUnits() -> [String] {
        return ["mg/dL", "g/dL", "mmol/L", "mEq/L", "IU/L", "U/L", "ng/mL", "pg/mL", "μg/dL", "ng/dL", "μIU/mL", "mIU/L", "K/uL", "M/uL", "%", "fL", "pg", "sec", "mm/hr", "mL/min/1.73m²"].sorted()
    }

    func getUnitsForTestType(_ testKey: String) -> [String] {
        guard let parameter = BloodTestResult.standardizedLabParameters[testKey] else {
            return getCommonUnits()
        }
        var units = getCommonUnits()
        if let preferredUnit = parameter.unit, !units.contains(preferredUnit) {
            units.insert(preferredUnit, at: 0)
        }
        return units
    }

    private func setupDefaultData() {
        commonLaboratories = ["LabCorp", "Quest Diagnostics", "Mayo Clinic Laboratories", "Cleveland Clinic", "Kaiser Permanente Lab", "ARUP Laboratories", "BioReference Laboratories"]
        commonPhysicians = ["Dr. Smith", "Dr. Johnson", "Dr. Williams", "Dr. Brown", "Dr. Davis", "Dr. Miller"]
    }
}

struct BloodTestTypeOption: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let displayName: String
    let unit: String?
    let referenceRange: String?
    let category: BloodTestCategory
    let description: String?
}

// MARK: - Simplified Dropdown Components (Inline)

struct SearchableDropdownWithAddNew: View {
    let title: String
    let items: [String]
    @Binding var selectedValue: String
    let onAddNew: (String) -> Void

    @State private var isShowingDropdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: $selectedValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)

                Button(action: {
                    isShowingDropdown.toggle()
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isShowingDropdown)
                }
            }

            if isShowingDropdown {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.self) { item in
                            Button(action: {
                                selectedValue = item
                                isShowingDropdown = false
                            }) {
                                HStack {
                                    Text(item)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedValue == item {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .background(selectedValue == item ? Color(.systemGray5) : Color.clear)

                            if item != items.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(radius: 2)
            }
        }
    }
}

struct TestTypeDropdown: View {
    @Binding var selectedTest: BloodTestTypeOption?
    @Binding var customTestName: String
    let onTestSelected: (BloodTestTypeOption) -> Void

    @State private var isShowingDropdown = false
    @StateObject private var dataManager = BloodTestDataManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Test Name (e.g., Glucose, Cholesterol)", text: $customTestName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)

                Button(action: {
                    isShowingDropdown.toggle()
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isShowingDropdown)
                }
            }

            if isShowingDropdown {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(dataManager.getStandardizedTestTypes().prefix(20)) { test in
                            Button(action: {
                                selectedTest = test
                                customTestName = test.displayName
                                onTestSelected(test)
                                isShowingDropdown = false
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(test.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedTest?.id == test.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }

                                    if let unit = test.unit {
                                        Text("Unit: \(unit)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .background(selectedTest?.id == test.id ? Color(.systemGray5) : Color.clear)

                            if test.id != dataManager.getStandardizedTestTypes().prefix(20).last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(radius: 2)
            }
        }
    }
}

struct UnitDropdown: View {
    @Binding var selectedUnit: String
    let testKey: String?

    @State private var isShowingDropdown = false
    @StateObject private var dataManager = BloodTestDataManager.shared

    private var availableUnits: [String] {
        if let testKey = testKey {
            return dataManager.getUnitsForTestType(testKey)
        }
        return dataManager.getCommonUnits()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Unit", text: $selectedUnit)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: 120)

                Button(action: {
                    isShowingDropdown.toggle()
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isShowingDropdown)
                }
            }

            if isShowingDropdown {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(availableUnits.prefix(10), id: \.self) { unit in
                            Button(action: {
                                selectedUnit = unit
                                isShowingDropdown = false
                            }) {
                                HStack {
                                    Text(unit)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedUnit == unit {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .background(selectedUnit == unit ? Color(.systemGray5) : Color.clear)

                            if unit != availableUnits.prefix(10).last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(radius: 2)
            }
        }
    }
}

struct BloodTestEntryView: View {
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

    @State private var selectedTestType: BloodTestTypeOption?
    @State private var selectedUnit: String = ""

    @StateObject private var dataManager = BloodTestDataManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Test Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TestTypeDropdown(
                    selectedTest: $selectedTestType,
                    customTestName: Binding(
                        get: { item.name },
                        set: { newValue in
                            item.name = newValue
                            validateName(newValue)
                        }
                    ),
                    onTestSelected: { testType in
                        selectedTestType = testType
                        item.name = testType.displayName
                        item.category = testType.category

                        // Auto-fill unit and reference range if available
                        if let unit = testType.unit {
                            selectedUnit = unit
                            item.unit = unit
                        }
                        if let referenceRange = testType.referenceRange {
                            item.referenceRange = referenceRange
                        }

                        validateName(testType.displayName)
                    }
                )
                .accessibilityIdentifier("bloodTestItem.testTypeDropdown")

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
            }

            Toggle("Abnormal Result", isOn: $item.isAbnormal)
                .font(.subheadline)
                .accessibilityIdentifier("bloodTestItem.abnormalToggle")
        }
        .padding(.vertical, 4)
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
