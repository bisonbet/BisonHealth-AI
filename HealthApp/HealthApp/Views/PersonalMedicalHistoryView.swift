import SwiftUI

struct PersonalMedicalHistoryView: View {
    @Binding var conditions: [MedicalCondition]

    var body: some View {
        List {
            ForEach($conditions) { $condition in
                NavigationLink(destination: MedicalConditionEditorView(condition: $condition)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(condition.name)
                            .font(.headline)

                        HStack {
                            Text(condition.status.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(backgroundColorForStatus(condition.status))
                                .foregroundColor(foregroundColorForStatus(condition.status))
                                .cornerRadius(4)

                            if let severity = condition.severity {
                                Text(severity.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        if let diagnosedDate = condition.diagnosedDate {
                            Text("Diagnosed: \(DateFormatter.mediumDate.string(from: diagnosedDate))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                conditions.remove(atOffsets: indexSet)
            }
        }
        .navigationTitle("Personal Medical History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addCondition) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func addCondition() {
        let newCondition = MedicalCondition(name: "")
        conditions.append(newCondition)
    }

    private func backgroundColorForStatus(_ status: MedicalConditionStatus) -> Color {
        switch status {
        case .active: return .red.opacity(0.2)
        case .chronic: return .orange.opacity(0.2)
        case .monitoring: return .yellow.opacity(0.2)
        case .resolved: return .green.opacity(0.2)
        case .inactive: return .gray.opacity(0.2)
        }
    }

    private func foregroundColorForStatus(_ status: MedicalConditionStatus) -> Color {
        switch status {
        case .active: return .red
        case .chronic: return .orange
        case .monitoring: return .brown
        case .resolved: return .green
        case .inactive: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        PersonalMedicalHistoryView(conditions: .constant([
            MedicalCondition(name: "Hypertension", diagnosedDate: Date(), status: .chronic, severity: .moderate),
            MedicalCondition(name: "Seasonal Allergies", diagnosedDate: Date(), status: .active, severity: .mild)
        ]))
    }
}