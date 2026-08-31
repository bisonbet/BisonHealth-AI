import SwiftUI

// MARK: - Searchable Dropdown with Add New Option
struct SearchableDropdownWithAddNew: View {
    let title: String
    let items: [String]
    @Binding var selectedValue: String
    let onAddNew: (String) -> Void

    @State private var isShowingDropdown = false
    @State private var searchText = ""
    @State private var isShowingAddNew = false
    @State private var newItemText = ""

    private var filteredItems: [String] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: $selectedValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)

                Button(action: {
                    isShowingDropdown.toggle()
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isShowingDropdown)
                }
            }

            if isShowingDropdown {
                VStack(alignment: .leading, spacing: 0) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search \(title.lowercased())", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Add new option at the top if search text doesn't match existing
                            if !searchText.isEmpty && !filteredItems.contains(where: { $0.caseInsensitiveCompare(searchText) == .orderedSame }) {
                                Button(action: {
                                    selectedValue = searchText
                                    onAddNew(searchText)
                                    isShowingDropdown = false
                                    searchText = ""
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Add \"\(searchText)\"")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                }
                                .background(Color(.systemGray6))

                                Divider()
                            }

                            // Existing items
                            ForEach(filteredItems, id: \.self) { item in
                                Button(action: {
                                    selectedValue = item
                                    isShowingDropdown = false
                                    searchText = ""
                                }) {
                                    HStack {
                                        Text(item)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedValue == item {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(BisonTheme.gold)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                }
                                .background(selectedValue == item ? Color(.systemGray5) : Color.clear)

                                if item != filteredItems.last {
                                    Divider()
                                }
                            }

                            // Add new button at bottom
                            Button(action: {
                                isShowingAddNew = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(BisonTheme.gold)
                                    Text("Add New \(title)")
                                        .foregroundColor(BisonTheme.gold)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                            }
                            .background(Color(.systemGray6))
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(radius: 2)
            }
        }
        .alert("Add New \(title)", isPresented: $isShowingAddNew) {
            TextField("Enter \(title.lowercased())", text: $newItemText)
            Button("Add") {
                if !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedValue = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAddNew(selectedValue)
                    newItemText = ""
                    isShowingDropdown = false
                }
            }
            Button("Cancel", role: .cancel) {
                newItemText = ""
            }
        } message: {
            Text("Enter a new \(title.lowercased()) name")
        }
        .onTapGesture {
            // Close dropdown when tapping outside
            if isShowingDropdown {
                isShowingDropdown = false
                searchText = ""
            }
        }
    }
}

// MARK: - Unit Dropdown
struct UnitDropdown: View {
    @Binding var selectedUnit: String
    let testKey: String?

    @State private var isShowingDropdown = false
    @StateObject private var dataManager = BloodTestDataManager.shared

    private var availableUnits: [String] {
        if let testKey = testKey {
            return dataManager.getUnitsForTestType(testKey)
        }
        return dataManager.getCommonUnits()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Unit", text: $selectedUnit)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: 120)

                Button(action: {
                    isShowingDropdown.toggle()
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isShowingDropdown ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isShowingDropdown)
                }
            }

            if isShowingDropdown {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(availableUnits, id: \.self) { unit in
                            Button(action: {
                                selectedUnit = unit
                                isShowingDropdown = false
                            }) {
                                HStack {
                                    Text(unit)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedUnit == unit {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(BisonTheme.gold)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .background(selectedUnit == unit ? Color(.systemGray5) : Color.clear)

                            if unit != availableUnits.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .shadow(radius: 2)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SearchableDropdownWithAddNew(
            title: "Laboratory",
            items: ["LabCorp", "Quest Diagnostics", "Mayo Clinic"],
            selectedValue: .constant(""),
            onAddNew: { _ in }
        )

        UnitDropdown(
            selectedUnit: .constant(""),
            testKey: "glucose"
        )
    }
    .padding()
}