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
        VStack(alignment: .leading, spacing: 8) {
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
            
            if !personalInfo.allergies.isEmpty {
                InfoRow(
                    label: "Allergies",
                    value: personalInfo.allergies.joined(separator: ", "),
                    icon: "exclamationmark.triangle"
                )
            }
            
            if !personalInfo.medications.isEmpty {
                InfoRow(
                    label: "Medications",
                    value: "\(personalInfo.medications.count) active",
                    icon: "pills"
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Formatting Functions
    
    private func formatHeight(_ height: Measurement<UnitLength>) -> String {
        if UserDefaults.standard.bool(forKey: "useImperialUnits") {
            let totalInches = height.converted(to: .inches).value
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)' \(inches)\""
        } else {
            let cm = height.converted(to: .centimeters).value
            return "\(String(format: "%.0f", cm)) cm"
        }
    }
    
    private func formatWeight(_ weight: Measurement<UnitMass>) -> String {
        if UserDefaults.standard.bool(forKey: "useImperialUnits") {
            let lbs = weight.converted(to: .pounds).value
            return "\(String(format: "%.0f", lbs)) lbs"
        } else {
            let kg = weight.converted(to: .kilograms).value
            return "\(String(format: "%.1f", kg)) kg"
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

// MARK: - Extensions
// Note: mediumDate DateFormatter is already defined in DocumentProcessor.swift

#Preview {
    List {
        PersonalInfoSection(
            personalInfo: PersonalHealthInfo(
                name: "John Doe",
                dateOfBirth: Date(),
                gender: .male,
                bloodType: .oPositive
            ),
            onEdit: {}
        )
        
        PersonalInfoSection(
            personalInfo: nil,
            onEdit: {}
        )
    }
}