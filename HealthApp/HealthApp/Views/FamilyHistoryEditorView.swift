import SwiftUI

struct FamilyHistoryEditorView: View {
    @Binding var familyHistory: FamilyMedicalHistory

    var body: some View {
        Form {
            Section(header: Text("Parents")) {
                RelativeTextEditor(title: "Mother", text: $familyHistory.mother)
                RelativeTextEditor(title: "Father", text: $familyHistory.father)
            }
            
            Section(header: Text("Maternal Grandparents")) {
                RelativeTextEditor(title: "Grandmother", text: $familyHistory.maternalGrandmother)
                RelativeTextEditor(title: "Grandfather", text: $familyHistory.maternalGrandfather)
            }
            
            Section(header: Text("Paternal Grandparents")) {
                RelativeTextEditor(title: "Grandmother", text: $familyHistory.paternalGrandmother)
                RelativeTextEditor(title: "Grandfather", text: $familyHistory.paternalGrandfather)
            }
            
            Section(header: Text("Siblings")) {
                RelativeTextEditor(title: "Siblings (Consolidated)", text: $familyHistory.siblings)
            }
            
            Section(header: Text("Other Relatives")) {
                RelativeTextEditor(title: "Other", text: $familyHistory.other)
            }
        }
        .navigationTitle("Family Medical History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RelativeTextEditor: View {
    let title: String
    @Binding var text: String?
    @State private var isUnknown: Bool

    init(title: String, text: Binding<String?>) {
        self.title = title
        self._text = text
        self._isUnknown = State(initialValue: text.wrappedValue == nil)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: $isUnknown) {
                Text("\(title) History Unknown")
            }
            .onChange(of: isUnknown) {
                text = isUnknown ? nil : ""
            }

            if !isUnknown {
                TextEditor(text: Binding(
                    get: { text ?? "" },
                    set: { text = $0 }
                ))
                .frame(height: 100)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FamilyHistoryEditorView(familyHistory: .constant(FamilyMedicalHistory()))
    }
}
