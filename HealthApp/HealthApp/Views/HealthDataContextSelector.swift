import SwiftUI

struct HealthDataContextSelector: View {
    @Binding var selectedTypes: Set<HealthDataType>
    let onSave: (Set<HealthDataType>) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var localSelection: Set<HealthDataType>
    
    init(selectedTypes: Binding<Set<HealthDataType>>, onSave: @escaping (Set<HealthDataType>) -> Void) {
        self._selectedTypes = selectedTypes
        self.onSave = onSave
        self._localSelection = State(initialValue: selectedTypes.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select which health data types to include in your AI conversations. This helps provide more relevant and personalized responses.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Available Data Types") {
                    ForEach(HealthDataType.allCases, id: \.self) { dataType in
                        HealthDataTypeRow(
                            dataType: dataType,
                            isSelected: localSelection.contains(dataType),
                            onToggle: {
                                if localSelection.contains(dataType) {
                                    localSelection.remove(dataType)
                                } else {
                                    localSelection.insert(dataType)
                                }
                            }
                        )
                    }
                }
                
                if !localSelection.isEmpty {
                    Section("Context Size") {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Estimated Context Size")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("Medium - Good balance of detail and performance")
                                    .font(.caption2)
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Health Data Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        selectedTypes = localSelection
                        onSave(localSelection)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HealthDataTypeRow: View {
    let dataType: HealthDataType
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: dataType.icon)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(dataType.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(dataTypeDescription(for: dataType))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func dataTypeDescription(for type: HealthDataType) -> String {
        switch type {
        case .personalInfo:
            return "Basic demographics, allergies, medications"
        case .bloodTest:
            return "Lab results and blood work"
        case .imagingReport:
            return "X-rays, MRIs, CT scans"
        case .healthCheckup:
            return "Physical exams and checkups"
        }
    }
}

#Preview {
    HealthDataContextSelector(
        selectedTypes: .constant([.personalInfo, .bloodTest]),
        onSave: { _ in }
    )
}