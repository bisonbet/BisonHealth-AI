import SwiftUI

// MARK: - Blood Test Import Review View
struct BloodTestImportReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var importGroups: [BloodTestImportGroup]
    let onComplete: ([BloodTestImportGroup]) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var showingAcceptAllConfirmation = false
    /// Every choice the user makes on this sheet. A value type so the transitions the view
    /// performs are the ones the tests exercise (WS-15-12).
    @State private var selection: Selection
    @State private var showAutoAccepted = false

    init(
        importGroups: Binding<[BloodTestImportGroup]>,
        autoAcceptedGroups: [BloodTestImportGroup] = [],
        onComplete: @escaping ([BloodTestImportGroup]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self._importGroups = importGroups
        self._selection = State(initialValue: Selection(autoAcceptedGroups: autoAcceptedGroups))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    // Convenience initializer for non-binding usage
    init(
        importGroups: [BloodTestImportGroup],
        autoAcceptedGroups: [BloodTestImportGroup] = [],
        onComplete: @escaping ([BloodTestImportGroup]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self._importGroups = Binding(
            get: { importGroups },
            set: { _ in }
        )
        self._selection = State(initialValue: Selection(autoAcceptedGroups: autoAcceptedGroups))
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if !selection.autoAcceptedGroups.isEmpty {
                    autoAcceptedSection
                }

                ForEach($importGroups) { $group in
                    reviewGroupSection($group)
                }

                ForEach($selection.demotedGroups) { $group in
                    reviewGroupSection($group)
                }
            }
            .onAppear {
                selection.seed(from: importGroups)
            }
            .navigationTitle("Review Lab Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        // Discard the pending review so the queue can advance;
                        // the sheet is not swipe-dismissable (see below).
                        onCancel?()
                        dismiss()
                    }
                    .accessibilityIdentifier("importReviewCancelButton")
                }

                // Text on purpose: the count is the point of this button ("Import 3 of 5"), and
                // an icon would drop it. A text item stays in a horizontal bar on iPhone Duo.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedGroupCount) of \(totalGroupCount)") {
                        acceptSelected()
                    }
                    .accessibilityLabel("Import \(selectedGroupCount) of \(totalGroupCount) lab values")
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
            // The review is a data-entry form: prevent accidental swipe-dismiss
            // (which would strand the pending review at the queue head).
            .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Import Counts
    private var totalGroupCount: Int {
        selection.totalCount(importGroups: importGroups)
    }

    private var selectedGroupCount: Int {
        selection.selectedCount(importGroups: importGroups)
    }

    /// Groups that will be dropped — whether the user said so or simply has not
    /// decided. Shown explicitly, because silently discarding an abnormal result and
    /// then summarising the record as "All normal" is the worst outcome this sheet has.
    private var omittedGroupCount: Int {
        max(0, totalGroupCount - selectedGroupCount)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review \(totalGroupCount) extracted test results")
                    .font(.headline)

                Text("Please review values before importing. You can deselect items to ignore them.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if omittedGroupCount > 0 {
                    Label(
                        "\(omittedGroupCount) of \(totalGroupCount) will not be imported until you choose a value.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("importReviewOmittedNotice")
                }

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
                ForEach(selection.autoAcceptedGroups) { group in
                    autoAcceptedRow(group)
                }
            } label: {
                Label("Auto-imported (\(selection.autoAcceptedGroups.count) values)", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            .accessibilityLabel("Auto-imported values, \(selection.autoAcceptedGroups.count) items")
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
        selection.demote(group)
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
                if selection.isIgnored(group.wrappedValue.id) {
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
        let isSelected = selection.isIgnored(groupId)

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
            selection.ignore(groupId)
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
        let isSelected = selection.isSelected(candidate.id, in: group.wrappedValue)
        
        // Check if this candidate is the recommended one (matches the group's recommendedCandidate)
        let isRecommended = group.wrappedValue.recommendedCandidate?.id == candidate.id
        
        // Check if calculated
        let isCalculated = candidate.originalTestName.lowercased().contains("calc")
        
        return HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? BisonTheme.goldText : .gray)
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
            // Allow explicit selection of parseable values with a unit warning;
            // structurally invalid OCR values remain non-selectable.
            if selection.select(candidate, inGroup: group.wrappedValue.id) {
                // Update both the state and the binding
                var updatedGroup = group.wrappedValue
                updatedGroup.selectedCandidateId = candidate.id
                group.wrappedValue = updatedGroup
            }
        }
        .opacity(candidate.isSelectable ? 1.0 : 0.6)
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
        case .unitMismatch:
            return (.orange, "Unit Warning — tap to import")
        case .ocrUnitMismatch:
            return (.red, "OCR Unit Error — cannot import")
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
        // The completion receives every decided group: reviewed + demoted-then-decided
        // + still-auto-accepted (their selection was set by the reconciler). Resolved on
        // copies — the binding at the call sites is read-only, so mutating `importGroups`
        // here would write nowhere.
        onComplete(selection.resolved(importGroups: importGroups))
        dismiss()
    }

    private func acceptAllRecommended() {
        selection.acceptAllRecommended(in: importGroups)
        acceptSelected()
    }
}

// MARK: - Selection State
extension BloodTestImportReviewView {
    /// The sheet's selection state and every transition the view applies to it.
    ///
    /// FE-P0 was a no-op `Binding` that dropped the user's pick, and the fix after it marked
    /// every undecided group "Will Ignore" on appear. Both bugs lived in the view's wiring,
    /// which a test of a pure function fed hand-built state could not see. The view now
    /// holds one of these and calls nothing else, so testing it tests the wiring.
    struct Selection {
        /// groupId -> candidateId
        private(set) var selectedIds: [UUID: UUID] = [:]
        /// Explicit user choice to skip import. Never inferred.
        private(set) var ignoredGroupIds: Set<UUID> = []
        /// Imported without review (audit trail); the user can demote one back into review.
        private(set) var autoAcceptedGroups: [BloodTestImportGroup]
        /// Settable because the view edits these rows through a binding, as it does the
        /// reviewed groups.
        var demotedGroups: [BloodTestImportGroup] = []

        init(autoAcceptedGroups: [BloodTestImportGroup] = []) {
            self.autoAcceptedGroups = autoAcceptedGroups
        }

        /// Copies the reconciler's pre-selections in. A group with none is left UNDECIDED.
        /// They used to be inserted into `ignoredGroupIds`, which marked them "Will Ignore"
        /// in red before the user had looked at anything. Abnormal values never carry a
        /// pre-selection (`isRecommended` requires `!isAbnormal`), so exactly the results
        /// that matter most arrived pre-marked for discard, and one tap on Import Selected
        /// dropped them while saving a record that read "All normal".
        ///
        /// Safe to call on every appear: a choice the user has already made is kept.
        mutating func seed(from importGroups: [BloodTestImportGroup]) {
            for group in importGroups where selectedIds[group.id] == nil && !ignoredGroupIds.contains(group.id) {
                if let selectedCandidateId = group.selectedCandidateId {
                    selectedIds[group.id] = selectedCandidateId
                }
            }
        }

        func isIgnored(_ groupId: UUID) -> Bool {
            ignoredGroupIds.contains(groupId)
        }

        func isSelected(_ candidateId: UUID, in group: BloodTestImportGroup) -> Bool {
            !isIgnored(group.id) && (selectedIds[group.id] ?? group.selectedCandidateId) == candidateId
        }

        /// Picks `candidate`. Structurally invalid OCR values stay non-selectable; parseable
        /// values with a unit warning can be chosen explicitly. Returns whether it applied.
        @discardableResult
        mutating func select(_ candidate: BloodTestImportCandidate, inGroup groupId: UUID) -> Bool {
            guard candidate.isSelectable else { return false }
            ignoredGroupIds.remove(groupId)
            selectedIds[groupId] = candidate.id
            return true
        }

        mutating func ignore(_ groupId: UUID) {
            ignoredGroupIds.insert(groupId)
            selectedIds[groupId] = nil
        }

        /// Moves an auto-accepted group into review, marked ignored until the user picks:
        /// demoting is a request to look again, and nothing should import unseen.
        mutating func demote(_ group: BloodTestImportGroup) {
            autoAcceptedGroups.removeAll { $0.id == group.id }
            var demoted = group
            demoted.isAutoAccepted = false
            demoted.selectedCandidateId = nil
            demotedGroups.append(demoted)
            ignoredGroupIds.insert(demoted.id)
        }

        mutating func acceptAllRecommended(in importGroups: [BloodTestImportGroup]) {
            for group in importGroups + demotedGroups {
                if let recommended = group.recommendedCandidate {
                    selectedIds[group.id] = recommended.id
                    ignoredGroupIds.remove(group.id)
                }
            }
        }

        /// Every group the sheet is accounting for.
        func totalCount(importGroups: [BloodTestImportGroup]) -> Int {
            importGroups.count + demotedGroups.count + autoAcceptedGroups.count
        }

        /// Groups that will actually be written: ones the user selected, plus the
        /// auto-accepted ones, which import by definition.
        func selectedCount(importGroups: [BloodTestImportGroup]) -> Int {
            func chosen(_ groups: [BloodTestImportGroup]) -> Int {
                groups.filter { selectedIds[$0.id] != nil && !ignoredGroupIds.contains($0.id) }.count
            }
            return chosen(importGroups) + chosen(demotedGroups) + autoAcceptedGroups.count
        }

        /// The user's choices applied to COPIES of every group, in presentation order.
        func resolved(importGroups: [BloodTestImportGroup]) -> [BloodTestImportGroup] {
            func apply(_ groups: [BloodTestImportGroup]) -> [BloodTestImportGroup] {
                groups.map { group in
                    var group = group
                    if ignoredGroupIds.contains(group.id) {
                        group.selectedCandidateId = nil
                    } else if let selectedId = selectedIds[group.id] {
                        group.selectedCandidateId = selectedId
                    }
                    return group
                }
            }
            return apply(importGroups) + apply(demotedGroups) + apply(autoAcceptedGroups)
        }
    }
}
