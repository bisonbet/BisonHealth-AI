import SwiftUI

// MARK: - Unit Preference Helper
extension UserDefaults {
    var useImperialUnits: Bool {
        get { bool(forKey: "useImperialUnits") }
        set { set(newValue, forKey: "useImperialUnits") }
    }
}

struct PersonalInfoEditorView: View {
    let personalInfo: PersonalHealthInfo?
    let onSave: (PersonalHealthInfo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var editedInfo: PersonalHealthInfo
    
    // Measurement system preference
    @State private var useImperialUnits = UserDefaults.standard.useImperialUnits
    
    // Focus management to prevent keyboard constraint conflicts
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name
        case heightText
        case weightText
    }
    
    // Height states
    @State private var heightFeet = 5
    @State private var heightInches = 8
    @State private var heightCentimeters = 173.0
    @State private var heightTextInput = ""
    @State private var showHeightTextInput = false
    
    // Weight states
    @State private var weightPounds = 150.0
    @State private var weightKilograms = 68.0
    @State private var weightTextInput = ""
    @State private var showWeightTextInput = false
    
    // Validation states
    @State private var nameValidationError: String?
    @State private var heightValidationError: String?
    @State private var weightValidationError: String?
    @State private var dateOfBirthValidationError: String?

    // Debounce work items to avoid high-frequency updates during wheel scrolling
    @State private var heightUpdateWorkItem: DispatchWorkItem?
    @State private var weightUpdateWorkItem: DispatchWorkItem?
    
    init(personalInfo: PersonalHealthInfo?, onSave: @escaping (PersonalHealthInfo) -> Void) {
        self.personalInfo = personalInfo
        self.onSave = onSave
        self._editedInfo = State(initialValue: personalInfo ?? PersonalHealthInfo())
        
        // Initialize measurement values from existing data
        if let height = personalInfo?.height {
            let cmValue = height.converted(to: .centimeters).value
            self._heightCentimeters = State(initialValue: cmValue)
            let totalInches = cmValue / 2.54
            self._heightFeet = State(initialValue: Int(totalInches / 12))
            self._heightInches = State(initialValue: Int(totalInches.truncatingRemainder(dividingBy: 12)))
        }
        
        if let weight = personalInfo?.weight {
            let kgValue = weight.converted(to: .kilograms).value
            self._weightKilograms = State(initialValue: kgValue)
            self._weightPounds = State(initialValue: kgValue * 2.20462)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    VStack(alignment: .leading) {
                        TextField("Full Name", text: Binding(
                            get: { editedInfo.name ?? "" },
                            set: { newValue in
                                editedInfo.name = newValue.isEmpty ? nil : newValue
                                validateName(newValue)
                            }
                        ))
                        .focused($focusedField, equals: .name)
                        .onTapGesture {
                            // Dismiss keyboard from other fields before focusing
                            focusedField = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = .name
                            }
                        }
                        .accessibilityIdentifier("personalInfo.nameField")
                        
                        if let error = nameValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityIdentifier("personalInfo.nameError")
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        DatePicker(
                            "Date of Birth",
                            selection: Binding(
                                get: { editedInfo.dateOfBirth ?? Date() },
                                set: { newValue in
                                    editedInfo.dateOfBirth = newValue
                                    validateDateOfBirth(newValue)
                                }
                            ),
                            in: Date.distantPast...Date(),
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("personalInfo.dateOfBirthPicker")
                        
                        if let error = dateOfBirthValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityIdentifier("personalInfo.dateOfBirthError")
                        }
                    }
                    
                    Picker("Sex", selection: Binding(
                        get: { editedInfo.gender ?? .preferNotToSay },
                        set: { editedInfo.gender = $0 }
                    )) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                    
                    Picker("Blood Type", selection: Binding(
                        get: { editedInfo.bloodType ?? .unknown },
                        set: { editedInfo.bloodType = $0 }
                    )) {
                        ForEach(BloodType.allCases, id: \.self) { bloodType in
                            Text(bloodType.displayName).tag(bloodType)
                        }
                    }
                }
                
                Section("Physical Measurements") {
                    // Unit system toggle
                    Picker("Units", selection: $useImperialUnits) {
                        Text("Metric (cm, kg)").tag(false)
                        Text("Imperial (ft/in, lbs)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: useImperialUnits) { _, newValue in
                        // Dismiss any active keyboard first
                        focusedField = nil
                        
                        // Save preference to UserDefaults
                        UserDefaults.standard.useImperialUnits = newValue
                        
                        // Clear text inputs when switching units
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            heightTextInput = ""
                            weightTextInput = ""
                            showHeightTextInput = false
                            showWeightTextInput = false
                        }
                    }
                    
                    // Height input
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Height")
                                .font(.headline)
                            Spacer()
                            Button(showHeightTextInput ? "Use Picker" : "Type Value") {
                                // Dismiss keyboard before switching input modes
                                focusedField = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showHeightTextInput.toggle()
                                }
                            }
                            .font(.caption)
                        }
                        
                        if showHeightTextInput {
                            TextField(useImperialUnits ? "Height (e.g., 5.75 for 5'9\")" : "Height (cm)", text: $heightTextInput)
                                .keyboardType(.decimalPad)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .heightText)
                                .onTapGesture {
                                    // Smooth transition to height text input
                                    focusedField = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        focusedField = .heightText
                                    }
                                }
                                .onSubmit {
                                    if let value = Double(heightTextInput), value > 0 {
                                        if useImperialUnits {
                                            // Validate range (3'0" to 8'11")
                                            if value >= 3.0 && value <= 8.95 {
                                                let totalInches = value * 12
                                                heightFeet = Int(value)
                                                heightInches = Int((value - Double(heightFeet)) * 12)
                                                heightCentimeters = totalInches * 2.54
                                                updateHeight()
                                                heightTextInput = ""
                                                focusedField = nil
                                            }
                                        } else {
                                            // Validate range (100cm to 220cm)
                                            if value >= 100 && value <= 220 {
                                                heightCentimeters = value
                                                let totalInches = value / 2.54
                                                heightFeet = Int(totalInches / 12)
                                                heightInches = Int(totalInches.truncatingRemainder(dividingBy: 12))
                                                updateHeight()
                                                heightTextInput = ""
                                                focusedField = nil
                                            }
                                        }
                                    }
                                }
                        } else {
                            if useImperialUnits {
                                HStack {
                                    Picker("Feet", selection: $heightFeet) {
                                        ForEach(3...8, id: \.self) { feet in
                                            Text("\(feet) ft").tag(feet)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(maxWidth: .infinity)
                                    
                                    Picker("Inches", selection: $heightInches) {
                                        ForEach(0...11, id: \.self) { inches in
                                            Text("\(inches) in").tag(inches)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(maxWidth: .infinity)
                                }
                                .onChange(of: heightFeet) { _, _ in debounceHeightUpdate() }
                                .onChange(of: heightInches) { _, _ in debounceHeightUpdate() }
                            } else {
                                Picker("Height", selection: Binding(
                                    get: { Int(heightCentimeters.rounded()) },
                                    set: { value in
                                        heightCentimeters = Double(value)
                                        // Update imperial values when metric height changes
                                        let totalInches = heightCentimeters / 2.54
                                        heightFeet = Int(totalInches / 12)
                                        heightInches = Int(totalInches.truncatingRemainder(dividingBy: 12))
                                        debounceHeightUpdate()
                                    }
                                )) {
                                    ForEach(100...220, id: \.self) { cm in
                                        Text("\(cm) cm").tag(cm)
                                    }
                                }
                                .pickerStyle(.wheel)
                            }
                        }
                        
                        Text(currentHeightDisplay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let error = heightValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityIdentifier("personalInfo.heightError")
                        }
                    }
                    
                    // Weight input
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Weight")
                                .font(.headline)
                            Spacer()
                            Button(showWeightTextInput ? "Use Picker" : "Type Value") {
                                // Dismiss keyboard before switching input modes
                                focusedField = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showWeightTextInput.toggle()
                                }
                            }
                            .font(.caption)
                        }
                        
                        if showWeightTextInput {
                            TextField(useImperialUnits ? "Weight (lbs)" : "Weight (kg)", text: $weightTextInput)
                                .keyboardType(.decimalPad)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .weightText)
                                .onTapGesture {
                                    // Smooth transition to weight text input
                                    focusedField = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        focusedField = .weightText
                                    }
                                }
                                .onSubmit {
                                    if let value = Double(weightTextInput), value > 0 {
                                        if useImperialUnits {
                                            // Validate range (80lbs to 400lbs)
                                            if value >= 80 && value <= 400 {
                                                weightPounds = value
                                                weightKilograms = value / 2.20462
                                                updateWeight()
                                                weightTextInput = ""
                                                focusedField = nil
                                            }
                                        } else {
                                            // Validate range (35kg to 180kg)
                                            if value >= 35 && value <= 180 {
                                                weightKilograms = value
                                                weightPounds = value * 2.20462
                                                updateWeight()
                                                weightTextInput = ""
                                                focusedField = nil
                                            }
                                        }
                                    }
                                }
                        } else {
                            if useImperialUnits {
                                Picker("Weight", selection: Binding(
                                    get: { Int(weightPounds.rounded()) },
                                    set: { value in
                                        weightPounds = Double(value)
                                        weightKilograms = weightPounds / 2.20462
                                        debounceWeightUpdate()
                                    }
                                )) {
                                    ForEach(80...400, id: \.self) { lbs in
                                        Text("\(lbs) lbs").tag(lbs)
                                    }
                                }
                                .pickerStyle(.wheel)
                            } else {
                                Picker("Weight", selection: Binding(
                                    get: { Int(weightKilograms.rounded()) },
                                    set: { value in
                                        weightKilograms = Double(value)
                                        weightPounds = weightKilograms * 2.20462
                                        debounceWeightUpdate()
                                    }
                                )) {
                                    ForEach(35...180, id: \.self) { kg in
                                        Text("\(kg) kg").tag(kg)
                                    }
                                }
                                .pickerStyle(.wheel)
                            }
                        }
                        
                        Text(currentWeightDisplay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let error = weightValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityIdentifier("personalInfo.weightError")
                        }
                    }
                }
                
                Section("Medical Information") {
                    NavigationLink("Allergies (\(editedInfo.allergies.count))") {
                        AllergiesEditorView(allergies: $editedInfo.allergies)
                    }
                    
                    NavigationLink("Medications (\(editedInfo.medications.count))") {
                        MedicationsEditorView(medications: $editedInfo.medications)
                    }
                    
                    NavigationLink("Medical History (\(editedInfo.medicalHistory.count))") {
                        MedicalHistoryEditorView(conditions: $editedInfo.medicalHistory)
                    }
                    
                    NavigationLink("Emergency Contacts (\(editedInfo.emergencyContacts.count))") {
                        EmergencyContactsEditorView(contacts: $editedInfo.emergencyContacts)
                    }
                }
            }
            .navigationTitle("Personal Information")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Initialize measurement values from existing data when view appears
                initializeMeasurementValues()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(editedInfo)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                    .accessibilityIdentifier("personalInfo.saveButton")
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func updateHeight() {
        if useImperialUnits {
            let totalInches = Double(heightFeet * 12 + heightInches)
            heightCentimeters = totalInches * 2.54
        }
        // Always store in centimeters internally
        editedInfo.height = Measurement(value: heightCentimeters, unit: UnitLength.centimeters)
        validateHeight()
    }
    
    private func updateWeight() {
        // Always store in kilograms internally
        editedInfo.weight = Measurement(value: weightKilograms, unit: UnitMass.kilograms)
        validateWeight()
    }

    private func debounceHeightUpdate() {
        heightUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { updateHeight() }
        heightUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    
    private func debounceWeightUpdate() {
        weightUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { updateWeight() }
        weightUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    
    private var currentHeightDisplay: String {
        if useImperialUnits {
            return "\(heightFeet)' \(heightInches)\" (\(String(format: "%.0f", heightCentimeters)) cm)"
        } else {
            let totalInches = heightCentimeters / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(String(format: "%.0f", heightCentimeters)) cm (\(feet)' \(inches)\")"
        }
    }
    
    private var currentWeightDisplay: String {
        if useImperialUnits {
            return "\(String(format: "%.0f", weightPounds)) lbs (\(String(format: "%.1f", weightKilograms)) kg)"
        } else {
            return "\(String(format: "%.1f", weightKilograms)) kg (\(String(format: "%.0f", weightPounds)) lbs)"
        }
    }
    
    private func initializeMeasurementValues() {
        // Initialize measurement values from existing data when view appears
        if let height = editedInfo.height {
            let cmValue = height.converted(to: .centimeters).value
            heightCentimeters = cmValue
            let totalInches = cmValue / 2.54
            heightFeet = Int(totalInches / 12)
            heightInches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        }
        
        if let weight = editedInfo.weight {
            let kgValue = weight.converted(to: .kilograms).value
            weightKilograms = kgValue
            weightPounds = kgValue * 2.20462
        }
    }
    
    // MARK: - Validation Functions
    
    private func validateName(_ name: String) {
        nameValidationError = nil
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            return // Optional field, no error for empty
        }
        
        if trimmedName.count < 2 {
            nameValidationError = "Name must be at least 2 characters"
        } else if trimmedName.count > 100 {
            nameValidationError = "Name must be less than 100 characters"
        } else if !trimmedName.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "." || $0 == "-" || $0 == "'" }) {
            nameValidationError = "Name can only contain letters, spaces, periods, hyphens, and apostrophes"
        }
    }
    
    private func validateDateOfBirth(_ date: Date) {
        dateOfBirthValidationError = nil
        
        let calendar = Calendar.current
        let now = Date()
        
        // Check if date is in the future
        if date > now {
            dateOfBirthValidationError = "Date of birth cannot be in the future"
            return
        }
        
        // Check if age is reasonable (0-150 years)
        let ageComponents = calendar.dateComponents([.year], from: date, to: now)
        if let age = ageComponents.year {
            if age > 150 {
                dateOfBirthValidationError = "Please enter a valid date of birth"
            }
        }
    }
    
    private func validateHeight() {
        heightValidationError = nil
        
        if useImperialUnits {
            let totalInches = Double(heightFeet * 12 + heightInches)
            if totalInches < 36 { // 3 feet
                heightValidationError = "Height must be at least 3 feet"
            } else if totalInches > 107 { // 8'11"
                heightValidationError = "Height must be less than 9 feet"
            }
        } else {
            if heightCentimeters < 100 {
                heightValidationError = "Height must be at least 100 cm"
            } else if heightCentimeters > 220 {
                heightValidationError = "Height must be less than 220 cm"
            }
        }
    }
    
    private func validateWeight() {
        weightValidationError = nil
        
        if useImperialUnits {
            if weightPounds < 80 {
                weightValidationError = "Weight must be at least 80 lbs"
            } else if weightPounds > 400 {
                weightValidationError = "Weight must be less than 400 lbs"
            }
        } else {
            if weightKilograms < 35 {
                weightValidationError = "Weight must be at least 35 kg"
            } else if weightKilograms > 180 {
                weightValidationError = "Weight must be less than 180 kg"
            }
        }
    }
    
    private var isFormValid: Bool {
        return nameValidationError == nil &&
               heightValidationError == nil &&
               weightValidationError == nil &&
               dateOfBirthValidationError == nil
    }
}

// MARK: - Placeholder Editor Views
struct AllergiesEditorView: View {
    @Binding var allergies: [String]
    @State private var newAllergy = ""
    
    var body: some View {
        List {
            Section {
                ForEach(allergies.indices, id: \.self) { index in
                    TextField("Allergy", text: $allergies[index])
                }
                .onDelete { indexSet in
                    allergies.remove(atOffsets: indexSet)
                }
                
                HStack {
                    TextField("Add new allergy", text: $newAllergy)
                    Button("Add") {
                        if !newAllergy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            allergies.append(newAllergy.trimmingCharacters(in: .whitespacesAndNewlines))
                            newAllergy = ""
                        }
                    }
                    .disabled(newAllergy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Allergies")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MedicationsEditorView: View {
    @Binding var medications: [Medication]
    
    var body: some View {
        List {
            ForEach(medications) { medication in
                VStack(alignment: .leading) {
                    Text(medication.name)
                        .font(.headline)
                    if let dosage = medication.dosage {
                        Text(dosage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                medications.remove(atOffsets: indexSet)
            }
            
            Button("Add Medication") {
                medications.append(Medication(name: "New Medication"))
            }
        }
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MedicalHistoryEditorView: View {
    @Binding var conditions: [MedicalCondition]
    
    var body: some View {
        List {
            ForEach(conditions) { condition in
                VStack(alignment: .leading) {
                    Text(condition.name)
                        .font(.headline)
                    Text(condition.status.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onDelete { indexSet in
                conditions.remove(atOffsets: indexSet)
            }
            
            Button("Add Condition") {
                conditions.append(MedicalCondition(name: "New Condition"))
            }
        }
        .navigationTitle("Medical History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EmergencyContactsEditorView: View {
    @Binding var contacts: [EmergencyContact]
    
    var body: some View {
        List {
            ForEach(contacts) { contact in
                VStack(alignment: .leading) {
                    Text(contact.name)
                        .font(.headline)
                    Text(contact.phoneNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onDelete { indexSet in
                contacts.remove(atOffsets: indexSet)
            }
            
            Button("Add Contact") {
                contacts.append(EmergencyContact(name: "New Contact", phoneNumber: ""))
            }
        }
        .navigationTitle("Emergency Contacts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PersonalInfoEditorView(
        personalInfo: PersonalHealthInfo(name: "John Doe"),
        onSave: { _ in }
    )
}
