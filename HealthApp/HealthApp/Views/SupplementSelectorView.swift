import SwiftUI

struct SupplementSelectorView: View {
    @Binding var supplements: [Supplement]
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: SupplementCategory? = nil
    @State private var showingCustomSupplementEditor = false
    @State private var newCustomSupplement = Supplement(name: "")

    var filteredSupplements: [SupplementTemplate] {
        var filtered = SupplementTemplate.database

        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.commonUses.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search supplements...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding()

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    CategoryFilterButton(title: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }

                    ForEach(SupplementCategory.allCases, id: \.self) { category in
                        CategoryFilterButton(
                            title: category.displayName,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)

            Divider()

            // Supplements list
            List {
                Section {
                    Button(action: {
                        newCustomSupplement = Supplement(name: "")
                        showingCustomSupplementEditor = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add Custom Supplement")
                                .foregroundColor(.primary)
                        }
                    }
                }

                Section(header: Text("\(filteredSupplements.count) supplements")) {
                    ForEach(filteredSupplements) { template in
                        Button(action: {
                            addSupplement(from: template)
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(template.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(template.category.displayName)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(template.category.color)
                                        .cornerRadius(4)
                                }

                                HStack {
                                    Text("Default: \(template.defaultDosage.displayText), \(template.defaultFrequency.displayName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if !template.commonUses.isEmpty {
                                    Text(template.commonUses)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Add Supplement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingCustomSupplementEditor) {
            NavigationStack {
                SupplementEditorView(supplement: $newCustomSupplement)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingCustomSupplementEditor = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Add") {
                                supplements.append(newCustomSupplement)
                                showingCustomSupplementEditor = false
                                dismiss()
                            }
                            .disabled(newCustomSupplement.name.isEmpty)
                        }
                    }
            }
        }
    }

    private func addSupplement(from template: SupplementTemplate) {
        let newSupplement = template.toSupplement()
        supplements.append(newSupplement)
        dismiss()
    }
}

struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

#Preview {
    NavigationStack {
        SupplementSelectorView(supplements: .constant([]))
    }
}
