import SwiftUI

struct MedicationsListView: View {
    @Binding var medications: [Medication]
    
    var body: some View {
        List {
            ForEach($medications) { $medication in
                NavigationLink(destination: MedicationEditorView(medication: $medication)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(medication.name)
                            .font(.headline)
                        HStack {
                            Text(medication.dosage.displayText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(medication.frequency.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if medication.isOngoing {
                            Text("Ongoing")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else if let endDate = medication.endDate {
                            Text("Until \(endDate.displayText)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .onDelete {
                medications.remove(atOffsets: $0)
            }
        }
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Medication", systemImage: "plus", action: addMedication)
            }
        }
    }
    
    private func addMedication() {
        let newMedication = Medication(name: "")
        medications.append(newMedication)
    }
}

#Preview {
    NavigationStack {
        MedicationsListView(medications: .constant([
            Medication(name: "Test 1"),
            Medication(name: "Test 2")
        ]))
    }
}
