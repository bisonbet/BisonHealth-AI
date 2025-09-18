import SwiftUI

struct PersonalInfoSection: View {
    let personalInfo: PersonalHealthInfo?
    let onEdit: () -> Void
    
    var body: some View {
        Section {
            if let info = personalInfo {
                PersonalInfoRowView(personalInfo: info)
            } else {
                EmptyPersonalInfoView()
            }
        } header: {
            HStack {
                Label("Personal Information", systemImage: "person.fill")
                Spacer()
                Button("Edit") {
                    onEdit()
                }
                .font(.caption)
            }
        }
    }
}

struct PersonalInfoRowView: View {
    let personalInfo: PersonalHealthInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let name = personalInfo.name {
                    InfoRow(label: "Name", value: name, icon: "person")
                }
                
                if let dateOfBirth = personalInfo.dateOfBirth {
                    InfoRow(
                        label: "Date of Birth",
                        value: DateFormatter.mediumDate.string(from: dateOfBirth),
                        icon: "calendar"
                    )
                }
                
                if let gender = personalInfo.gender {
                    InfoRow(label: "Sex", value: gender.displayName, icon: "figure.dress.line.vertical.figure")
                }
                
                if let bloodType = personalInfo.bloodType {
                    InfoRow(label: "Blood Type", value: bloodType.displayName, icon: "drop.fill")
                }
            }
            
            Group {
                if let height = personalInfo.height {
                    InfoRow(
                        label: "Height",
                        value: formatHeight(height),
                        icon: "ruler"
                    )
                }
                
                if let weight = personalInfo.weight {
                    InfoRow(
                        label: "Weight",
                        value: formatWeight(weight),
                        icon: "scalemass"
                    )
                }
            }
            
            // Medical Information with checkmarks
            VStack(alignment: .leading, spacing: 8) {
                InfoRowHeader(label: "Medical Information", icon: "heart.text.square")

                HStack {
                    Spacer().frame(width: 28) // Indent to align with InfoRow
                    VStack(alignment: .leading, spacing: 4) {
                        CheckmarkInfoRow(
                            label: "Allergies",
                            hasData: !personalInfo.allergies.isEmpty,
                            icon: "exclamationmark.triangle"
                        )

                        CheckmarkInfoRow(
                            label: "Medications",
                            hasData: !personalInfo.medications.isEmpty,
                            icon: "pills"
                        )

                        CheckmarkInfoRow(
                            label: "Personal Medical History",
                            hasData: !personalInfo.personalMedicalHistory.isEmpty,
                            icon: "doc.text"
                        )

                        CheckmarkInfoRow(
                            label: "Family Medical History",
                            hasData: !isFamilyHistoryEmpty(personalInfo.familyHistory),
                            icon: "person.3"
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Helper Functions
    
    private func isFamilyHistoryEmpty(_ history: FamilyMedicalHistory) -> Bool {
        return (history.mother?.isEmpty ?? true) &&
               (history.father?.isEmpty ?? true) &&
               (history.maternalGrandmother?.isEmpty ?? true) &&
               (history.maternalGrandfather?.isEmpty ?? true) &&
               (history.paternalGrandmother?.isEmpty ?? true) &&
               (history.paternalGrandfather?.isEmpty ?? true) &&
               (history.siblings?.isEmpty ?? true) &&
               (history.other?.isEmpty ?? true)
    }
    
    private func formatHeight(_ height: Measurement<UnitLength>) -> String {
        if UserDefaults.standard.bool(forKey: "useImperialUnits") {
            let totalInches = height.converted(to: .inches).value
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)' \(inches)" // Corrected escaping for single quote
        } else {
            let cm = height.converted(to: .centimeters).value
            return "\(String(format: "%.0f", cm)) cm" // Corrected escaping for format specifier
        }
    }
    
    private func formatWeight(_ weight: Measurement<UnitMass>) -> String {
        if UserDefaults.standard.bool(forKey: "useImperialUnits") {
            let lbs = weight.converted(to: .pounds).value
            return "\(String(format: "%.0f", lbs)) lbs" // Corrected escaping for format specifier
        } else {
            let kg = weight.converted(to: .kilograms).value
            return "\(String(format: "%.1f", kg)) kg" // Corrected escaping for format specifier
        }
    }
}

struct MedicationRowView: View {
    let medication: Medication
    
    var body: some View {
        HStack {
            Spacer().frame(width: 28) // Indent to align with InfoRow
            VStack(alignment: .leading) {
                Text(medication.name).bold()
                Text("\(medication.dosage.value, specifier: "%.2g") \(medication.dosage.unit.displayName), \(medication.frequency.displayName)") // Corrected escaping for specifier and string interpolation
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct FamilyHistoryRowView: View {
    let history: FamilyMedicalHistory
    
    var body: some View {
        HStack {
            Spacer().frame(width: 28) // Indent
            VStack(alignment: .leading, spacing: 4) {
                if let mother = history.mother, !mother.isEmpty { Text("Mother: \(mother)") }
                if let father = history.father, !father.isEmpty { Text("Father: \(father)") }
                if let maternalGrandmother = history.maternalGrandmother, !maternalGrandmother.isEmpty { Text("Maternal Grandmother: \(maternalGrandmother)") }
                if let maternalGrandfather = history.maternalGrandfather, !maternalGrandfather.isEmpty { Text("Maternal Grandfather: \(maternalGrandfather)") }
                if let paternalGrandmother = history.paternalGrandmother, !paternalGrandmother.isEmpty { Text("Paternal Grandmother: \(paternalGrandmother)") }
                if let paternalGrandfather = history.paternalGrandfather, !paternalGrandfather.isEmpty { Text("Paternal Grandfather: \(paternalGrandfather)") }
                if let siblings = history.siblings, !siblings.isEmpty { Text("Siblings: \(siblings)") }
                if let other = history.other, !other.isEmpty { Text("Other: \(other)") }
            }
            .font(.caption)
        }
    }
}

struct EmptyPersonalInfoView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.plus")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No personal information added")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Tap Edit to add your personal health information")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
        }
    }
}

struct InfoRowHeader: View {
    let label: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

struct CheckmarkInfoRow: View {
    let label: String
    let hasData: Bool
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            if hasData {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
    }
}


// MARK: - Extensions
// Note: mediumDate DateFormatter is already defined in DocumentProcessor.swift

#Preview {
    List {
        PersonalInfoSection(
            personalInfo: PersonalHealthInfo(
                name: "John Doe",
                dateOfBirth: Date(),
                gender: .male,
                bloodType: .oPositive,
                allergies: ["Peanuts", "Dust"],
                medications: [Medication(name: "Test Med", dosage: Dosage(value: 50, unit: .mg), frequency: .daily)],
                personalMedicalHistory: [MedicalCondition(name: "Hypertension")],
                familyHistory: FamilyMedicalHistory(mother: "High blood pressure")
            ),
            onEdit: {}
        )

        PersonalInfoSection(
            personalInfo: nil,
            onEdit: {}
        )
    }
}
