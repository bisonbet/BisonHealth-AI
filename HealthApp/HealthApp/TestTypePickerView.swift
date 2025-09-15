import SwiftUI

struct TestTypePickerView: View {
    @Binding var selectedTest: BloodTestTypeOption?
    let onTestSelected: (BloodTestTypeOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedLetter: String?

    @StateObject private var dataManager = BloodTestDataManager.shared

    // Computed properties
    private var allTests: [BloodTestTypeOption] {
        dataManager.getStandardizedTestTypes()
    }

    private var filteredTests: [BloodTestTypeOption] {
        if searchText.isEmpty {
            return allTests
        }

        return allTests.filter { test in
            test.displayName.localizedCaseInsensitiveContains(searchText) ||
            test.description?.localizedCaseInsensitiveContains(searchText) == true ||
            test.category.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedTests: [(String, [BloodTestTypeOption])] {
        let grouped = Dictionary(grouping: filteredTests) { test in
            String(test.displayName.prefix(1).uppercased())
        }

        return grouped.sorted { $0.key < $1.key }.map { (key, tests) in
            (key, tests.sorted { $0.displayName < $1.displayName })
        }
    }

    private var alphabetLetters: [String] {
        return Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }
    }

    private var availableLetters: Set<String> {
        return Set(groupedTests.map { $0.0 })
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Main content area
                    VStack(spacing: 0) {
                        // Test list
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                    ForEach(groupedTests, id: \.0) { letter, tests in
                                        Section {
                                            ForEach(tests) { test in
                                                TestTypeRow(
                                                    test: test,
                                                    isSelected: selectedTest?.id == test.id,
                                                    onTap: {
                                                        selectedTest = test
                                                        onTestSelected(test)
                                                        dismiss()
                                                    }
                                                )
                                                .padding(.horizontal, 16)

                                                if test.id != tests.last?.id {
                                                    Divider()
                                                        .padding(.leading, 16)
                                                }
                                            }
                                        } header: {
                                            SectionHeaderView(letter: letter)
                                        }
                                        .id(letter)
                                    }
                                }
                            }
                            .onChange(of: selectedLetter) { _, newLetter in
                                if let letter = newLetter, availableLetters.contains(letter) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        scrollProxy.scrollTo(letter, anchor: .top)
                                    }
                                }
                            }
                        }

                        // Search bar at bottom
                        SearchBarView(searchText: $searchText)
                    }

                    // Alphabetical index on the right
                    AlphabeticalIndexView(
                        availableLetters: availableLetters,
                        selectedLetter: $selectedLetter
                    )
                    .frame(width: 30)
                }
            }
            .navigationTitle("Select Test Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if !searchText.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            searchText = ""
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct TestTypeRow: View {
    let test: BloodTestTypeOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(test.displayName)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(.primary)

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(test.category.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)

                        if let unit = test.unit {
                            Text("Unit: \(unit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    if let referenceRange = test.referenceRange {
                        Text("Reference: \(referenceRange)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(isSelected ? Color(.systemGray6) : Color.clear)
    }
}

struct SectionHeaderView: View {
    let letter: String

    var body: some View {
        HStack {
            Text(letter)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

struct SearchBarView: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search test types...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray4)),
            alignment: .top
        )
    }
}

struct AlphabeticalIndexView: View {
    let availableLetters: Set<String>
    @Binding var selectedLetter: String?

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let alphabetLetters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 1) {
                ForEach(alphabetLetters, id: \.self) { letter in
                    Button(action: {
                        if availableLetters.contains(letter) {
                            selectedLetter = letter
                            hapticFeedback()
                        }
                    }) {
                        Text(letter)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(availableLetters.contains(letter) ? .blue : .gray)
                            .frame(width: 20, height: geometry.size.height / CGFloat(alphabetLetters.count))
                            .background(
                                selectedLetter == letter ? Color.blue.opacity(0.2) : Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                        }

                        let letterHeight = geometry.size.height / CGFloat(alphabetLetters.count)
                        let index = min(max(Int(value.location.y / letterHeight), 0), alphabetLetters.count - 1)
                        let letter = alphabetLetters[index]

                        if availableLetters.contains(letter) && selectedLetter != letter {
                            selectedLetter = letter
                            hapticFeedback()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .padding(.vertical, 8)
    }

    private func hapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Enhanced Test Type Button

struct TestTypeButton: View {
    let selectedTest: BloodTestTypeOption?
    let customTestName: String
    @Binding var isShowingPicker: Bool

    var body: some View {
        Button(action: {
            isShowingPicker = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let test = selectedTest {
                        Text(test.displayName)
                            .font(.body)
                            .foregroundColor(.primary)

                        HStack {
                            Text(test.category.displayName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)

                            if let unit = test.unit {
                                Text("• \(unit)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if !customTestName.isEmpty {
                        Text(customTestName)
                            .font(.body)
                            .foregroundColor(.primary)

                        Text("Custom test")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Select test type")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TestTypePickerView(
            selectedTest: .constant(nil),
            onTestSelected: { _ in }
        )
    }
}