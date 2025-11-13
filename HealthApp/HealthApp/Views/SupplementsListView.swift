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
                                .background(supplement.category.color)
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
}

#Preview {
    NavigationStack {
        SupplementsListView(supplements: .constant([
            Supplement(name: "Vitamin D3", category: .vitamin, dosage: Dosage(value: 2000, unit: .iu)),
            Supplement(name: "Omega-3 Fish Oil", category: .fattyAcid, dosage: Dosage(value: 1000, unit: .mg))
        ]))
    }
}
