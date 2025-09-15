
import SwiftUI

struct DoctorSelectorView: View {
    @Binding var selectedDoctor: Doctor?
    let onSave: (Doctor) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var localSelection: Doctor?

    init(selectedDoctor: Binding<Doctor?>, onSave: @escaping (Doctor) -> Void) {
        self._selectedDoctor = selectedDoctor
        self.onSave = onSave
        self._localSelection = State(initialValue: selectedDoctor.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Text("Select a Doctor")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Done") {
                        if let selection = localSelection {
                            onSave(selection)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))

                List(Doctor.defaultDoctors) { doctor in
                    DoctorRow(
                        doctor: doctor,
                        isSelected: localSelection?.id == doctor.id,
                        onSelect: {
                            localSelection = doctor
                        }
                    )
                }
            }
        }
    }
}

struct DoctorRow: View {
    let doctor: Doctor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(doctor.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(doctor.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    DoctorSelectorView(
        selectedDoctor: .constant(Doctor.defaultDoctors.first!), 
        onSave: { _ in }
    )
}
