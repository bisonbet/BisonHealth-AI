import SwiftUI

struct SupplementsListView: View {
    @Binding var supplements: [Supplement]
    @State private var showingSupplementSelector = false

    var body: some View {
        List {
            ForEach($supplements) { $supplement in
                NavigationLink(destination: SupplementEditorView(supplement: $supplement)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(supplement.name)
                            .font(.headline)
                        HStack {
                            Text(supplement.category.displayName)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(categoryColor(for: supplement.category))
                                .cornerRadius(4)
                            Text(supplement.dosage.displayText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(supplement.frequency.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onDelete {
                supplements.remove(atOffsets: $0)
            }
        }
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSupplementSelector = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingSupplementSelector) {
            NavigationStack {
                SupplementSelectorView(supplements: $supplements)
            }
        }
    }

    private func categoryColor(for category: SupplementCategory) -> Color {
        switch category {
        case .vitamin: return .purple
        case .mineral: return .orange
        case .herb: return .green
        case .aminoAcid: return .blue
        case .fattyAcid: return .teal
        case .probiotic: return .pink
        case .protein: return .red
        case .fiber: return .brown
        case .other: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        SupplementsListView(supplements: .constant([
            Supplement(name: "Vitamin D3", category: .vitamin, dosage: Dosage(value: 2000, unit: .iu)),
            Supplement(name: "Omega-3 Fish Oil", category: .fattyAcid, dosage: Dosage(value: 1000, unit: .mg))
        ]))
    }
}
