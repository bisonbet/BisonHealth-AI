import SwiftUI

// MARK: - Blood Test Import Review View
struct BloodTestImportReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var importGroups: [BloodTestImportGroup]
    let onComplete: ([BloodTestImportGroup]) -> Void

    @State private var showingAcceptAllConfirmation = false
    @State private var selectedIds: [UUID: UUID] = [:] // groupId -> candidateId
    @State private var ignoredGroupIds: Set<UUID> = [] // explicit user choice to skip import

    // Auto-accepted groups (audit trail); the user can demote one back into review
    @State private var autoAcceptedGroups: [BloodTestImportGroup]
    @State private var demotedGroups: [BloodTestImportGroup] = []
    @State private var showAutoAccepted = false

    init(
        importGroups: Binding<[BloodTestImportGroup]>,
        autoAcceptedGroups: [BloodTestImportGroup] = [],
        onComplete: @escaping ([BloodTestImportGroup]) -> Void
    ) {
        self._importGroups = importGroups
        self._autoAcceptedGroups = State(initialValue: autoAcceptedGroups)
        self.onComplete = onComplete
    }

    // Convenience initializer for non-binding usage
    init(
        importGroups: [BloodTestImportGroup],
        autoAcceptedGroups: [BloodTestImportGroup] = [],
        onComplete: @escaping ([BloodTestImportGroup]) -> Void
    ) {
        self._importGroups = Binding(
            get: { importGroups },
            set: { _ in }
        )
        self._autoAcceptedGroups = State(initialValue: autoAcceptedGroups)
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if !autoAcceptedGroups.isEmpty {
                    autoAcceptedSection
                }

                ForEach($importGroups) { $group in
                    reviewGroupSection($group)
                }

                ForEach($demotedGroups) { $group in
                    reviewGroupSection($group)
                }
            }
            .onAppear {
                // Initialize selectedIds from groups' selectedCandidateId
                for group in importGroups {
                    if let selectedCandidateId = group.selectedCandidateId {
                        selectedIds[group.id] = selectedCandidateId
                    } else {
                        ignoredGroupIds.insert(group.id)
                    }
                }
            }
            .navigationTitle("Review Lab Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("importReviewCancelButton")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import Selected") {
                        acceptSelected()
                    }
                    .accessibilityLabel("Import selected lab values")
                    .accessibilityHint("Saves the selected values plus all auto-imported values to your health records")
                    .accessibilityIdentifier("importSelectedButton")
                }
            }
            .confirmationDialog(
                "Accept All Recommended",
                isPresented: $showingAcceptAllConfirmation
            ) {
                Button("Accept All Recommended", role: .none) {
                    acceptAllRecommended()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will accept all recommended values (highlighted in green).")
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review \(importGroups.count + demotedGroups.count) extracted test results")
                    .font(.headline)

                Text("Please review values before importing. You can deselect items to ignore them.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Accept All Recommended") {
                    showingAcceptAllConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Accept all recommended values")
                .accessibilityIdentifier("acceptAllRecommendedButton")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Auto-Accepted Section (audit trail)
    private var autoAcceptedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAutoAccepted) {
                ForEach(autoAcceptedGroups) { group in
                    autoAcceptedRow(group)
                }
            } label: {
                Label("Auto-imported (\(autoAcceptedGroups.count) values)", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            .accessibilityLabel("Auto-imported values, \(autoAcceptedGroups.count) items")
            .accessibilityHint("Expands to show values that passed validation and will import automatically")
            .accessibilityIdentifier("autoImportedSection")
        } footer: {
            Text("These values had a single extracted result that passed validation. Tap one to review it instead.")
                .font(.caption2)
        }
    }

    private func autoAcceptedRow(_ group: BloodTestImportGroup) -> some View {
        let candidate = group.candidates.first

        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.standardTestName)
                    .font(.subheadline)
                if let candidate {
                    Text(candidate.displayValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("Review instead")
                .font(.caption)
                .foregroundColor(.accentColor)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            demoteAutoAcceptedGroup(group)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.standardTestName), \(candidate?.displayValue ?? ""), auto-imported")
        .accessibilityHint("Double tap to review this value manually instead of importing automatically")
    }

    private func demoteAutoAcceptedGroup(_ group: BloodTestImportGroup) {
        AppLog.shared.ui("User demoted auto-accepted group '\(group.standardTestName)' to manual review")
        autoAcceptedGroups.removeAll { $0.id == group.id }

        var demoted = group
        demoted.isAutoAccepted = false
        demoted.selectedCandidateId = nil
        demotedGroups.append(demoted)
        ignoredGroupIds.insert(demoted.id)
    }

    // MARK: - Review Group Section
    private func reviewGroupSection(_ group: Binding<BloodTestImportGroup>) -> some View {
        Section {
            testGroupView(group)
        } header: {
            HStack {
                Text(group.wrappedValue.standardTestName)
                    .font(.headline)
                Spacer()
                if ignoredGroupIds.contains(group.wrappedValue.id) {
                    Text("Will Ignore")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Test Group View
    private func testGroupView(_ group: Binding<BloodTestImportGroup>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if group.wrappedValue.hasMultipleDistinctValues {
                multipleValuesWarning
            }

            ForEach(group.wrappedValue.candidates) { candidate in
                candidateRow(candidate, group: group)
            }

            // "Don't Import" Option
            dontImportRow(group: group)
        }
    }

    // MARK: - Multiple Values Warning
    private var multipleValuesWarning: some View {
        Label("Multiple values found — likely an OCR or extraction duplicate. Pick the correct one.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.12))
            )
            .accessibilityLabel("Warning: multiple values were extracted for this test, likely a duplicate. Pick the correct one.")
    }
    
    // MARK: - Don't Import Row
    private func dontImportRow(group: Binding<BloodTestImportGroup>) -> some View {
        let groupId = group.wrappedValue.id
        let isSelected = ignoredGroupIds.contains(groupId)

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .red : .gray)
                .font(.title3)

            Text("Don't import this result")
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            AppLog.shared.ui("🔘 Don't import tapped for group: \(groupId)")
            // Update state dictionary
            ignoredGroupIds.insert(groupId)
            selectedIds[groupId] = nil
            // Update binding
            var updatedGroup = group.wrappedValue
            updatedGroup.selectedCandidateId = nil
            group.wrappedValue = updatedGroup
        }
        .allowsHitTesting(true)
        .zIndex(1)
    }
    
    // MARK: - Candidate Row
    private func candidateRow(_ candidate: BloodTestImportCandidate, group: Binding<BloodTestImportGroup>) -> some View {
        // Use selectedIds state if available, otherwise fall back to group's selectedCandidateId
        let groupId = group.wrappedValue.id
        let currentSelection = selectedIds[groupId] ?? group.wrappedValue.selectedCandidateId
        let isSelected = !ignoredGroupIds.contains(groupId) && currentSelection == candidate.id
        
        // Check if this candidate is the recommended one (matches the group's recommendedCandidate)
        let isRecommended = group.wrappedValue.recommendedCandidate?.id == candidate.id
        
        // Check if calculated
        let isCalculated = candidate.originalTestName.lowercased().contains("calc")
        
        return HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? BisonTheme.gold : .gray)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                // Value display
                HStack {
                    Text(candidate.displayValue)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isRecommended {
                        Label("Recommended", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if isCalculated {
                        Text("Calculated")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(BisonTheme.gold.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                // Original test name
                Text(candidate.originalTestName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Validation status
                if candidate.validationStatus != .valid {
                    validationStatusBadge(candidate.validationStatus, reason: candidate.reason)
                }
                
                // Confidence and reference range
                HStack(spacing: 12) {
                    // Always show confidence if extracted via AI
                    Text("Confidence: \(Int(candidate.confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(candidate.confidence > 0.9 ? .secondary : .orange)

                    if let range = candidate.referenceRange {
                        Text("Expected: \(range)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Provenance: which extraction pass found it, and where
                if let provenance = candidate.provenanceDescription {
                    Text(provenance)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let snippet = candidate.sourceSnippet {
                    Text(snippet)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray6))
                        )
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? BisonTheme.gold.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? BisonTheme.gold : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .clipped()
        .onTapGesture {
            AppLog.shared.ui("Candidate tapped: \(candidate.displayValue)")
            // Only allow selection of valid candidates
            if candidate.validationStatus == .valid {
                // Update both the state and the binding
                ignoredGroupIds.remove(groupId)
                selectedIds[groupId] = candidate.id
                var updatedGroup = group.wrappedValue
                updatedGroup.selectedCandidateId = candidate.id
                group.wrappedValue = updatedGroup
            }
        }
        .opacity(candidate.validationStatus == .valid ? 1.0 : 0.6)
        .zIndex(0)
    }
    
    // MARK: - Validation Status Badge
    private func validationStatusBadge(_ status: BloodTestImportCandidate.ValidationStatus, reason: String?) -> some View {
        let (color, text) = statusDisplay(status)
        
        return HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2)
            if let reason = reason {
                Text("• \(reason)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.2))
        )
    }
    
    private func statusDisplay(_ status: BloodTestImportCandidate.ValidationStatus) -> (Color, String) {
        switch status {
        case .valid:
            return (.green, "Valid")
        case .invalidType:
            return (.red, "Invalid Type")
        case .outOfRange:
            return (.orange, "Out of Range")
        case .missingData:
            return (.yellow, "Missing Data")
        }
    }
    
    // MARK: - Actions
    private func acceptSelected() {
        // Update all groups with the selected IDs from state
        for index in importGroups.indices {
            let groupId = importGroups[index].id

            if ignoredGroupIds.contains(groupId) {
                importGroups[index].selectedCandidateId = nil
                continue
            }

            if let selectedId = selectedIds[groupId] {
                importGroups[index].selectedCandidateId = selectedId
            }
            // If not in selectedIds, keep existing selectedCandidateId
        }

        var resolvedDemoted = demotedGroups
        for index in resolvedDemoted.indices {
            let groupId = resolvedDemoted[index].id
            if ignoredGroupIds.contains(groupId) {
                resolvedDemoted[index].selectedCandidateId = nil
            } else if let selectedId = selectedIds[groupId] {
                resolvedDemoted[index].selectedCandidateId = selectedId
            }
        }

        // The completion receives every decided group: reviewed + demoted-then-decided
        // + still-auto-accepted (their selection was set by the reconciler)
        onComplete(importGroups + resolvedDemoted + autoAcceptedGroups)
        dismiss()
    }

    private func acceptAllRecommended() {
        // Update selectedIds state with all recommended candidates
        for group in importGroups + demotedGroups {
            if let recommended = group.recommendedCandidate {
                selectedIds[group.id] = recommended.id
                ignoredGroupIds.remove(group.id)
            } else if let firstValid = group.candidates.first(where: { $0.validationStatus == .valid }) {
                selectedIds[group.id] = firstValid.id
                ignoredGroupIds.remove(group.id)
            }
        }
        acceptSelected()
    }
}