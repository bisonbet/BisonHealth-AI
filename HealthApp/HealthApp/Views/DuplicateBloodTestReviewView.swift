import SwiftUI

// MARK: - Duplicate Blood Test Review View
struct DuplicateBloodTestReviewView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var duplicateGroups: [DuplicateTestGroup]
    let onComplete: ([DuplicateTestGroup]) -> Void
    
    @State private var showingAcceptAllConfirmation = false
    @State private var selectedIds: [UUID: UUID] = [:] // groupId -> candidateId
    
    init(duplicateGroups: Binding<[DuplicateTestGroup]>, onComplete: @escaping ([DuplicateTestGroup]) -> Void) {
        self._duplicateGroups = duplicateGroups
        self.onComplete = onComplete
    }
    
    // Convenience initializer for non-binding usage
    init(duplicateGroups: [DuplicateTestGroup], onComplete: @escaping ([DuplicateTestGroup]) -> Void) {
        self._duplicateGroups = Binding(
            get: { duplicateGroups },
            set: { _ in }
        )
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationStack {
            List {
                headerSection
                
                ForEach($duplicateGroups) { $group in
                    Section {
                        testGroupView($group)
                    } header: {
                        Text(group.standardTestName)
                            .font(.headline)
                    }
                }
            }
            .onAppear {
                // Initialize selectedIds from groups' selectedCandidateId
                for group in duplicateGroups {
                    if let selectedId = group.selectedCandidateId {
                        selectedIds[group.id] = selectedId
                    }
                }
            }
            .navigationTitle("Review Duplicate Values")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Accept Selected") {
                        acceptSelected()
                    }
                    .disabled(!hasValidSelections)
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
                Text("This will accept all recommended values (highlighted in green) and discard the others.")
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Found \(duplicateGroups.count) test(s) with duplicate values")
                    .font(.headline)
                
                Text("Please review and select the correct value for each test. Recommended values are highlighted in green.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Accept All Recommended") {
                    showingAcceptAllConfirmation = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Test Group View
    private func testGroupView(_ group: Binding<DuplicateTestGroup>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(group.wrappedValue.candidates) { candidate in
                candidateRow(candidate, group: group)
            }
        }
    }
    
    // MARK: - Candidate Row
    private func candidateRow(_ candidate: DuplicateBloodTestCandidate, group: Binding<DuplicateTestGroup>) -> some View {
        // Use selectedIds state if available, otherwise fall back to group's selectedCandidateId
        let currentSelection = selectedIds[group.wrappedValue.id] ?? group.wrappedValue.selectedCandidateId
        let isSelected = currentSelection == candidate.id
        
        // Check if this candidate is the recommended one (matches the group's recommendedCandidate)
        let isRecommended = group.wrappedValue.recommendedCandidate?.id == candidate.id
        
        return HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray)
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
                    if candidate.confidence < 1.0 {
                        Text("Confidence: \(Int(candidate.confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let range = candidate.referenceRange {
                        Text("Range: \(range)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Only allow selection of valid candidates
            if candidate.validationStatus == .valid {
                // Update both the state and the binding
                selectedIds[group.wrappedValue.id] = candidate.id
                var updatedGroup = group.wrappedValue
                updatedGroup.selectedCandidateId = candidate.id
                group.wrappedValue = updatedGroup
            }
        }
        .opacity(candidate.validationStatus == .valid ? 1.0 : 0.6)
    }
    
    // MARK: - Validation Status Badge
    private func validationStatusBadge(_ status: DuplicateBloodTestCandidate.ValidationStatus, reason: String?) -> some View {
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
    
    private func statusDisplay(_ status: DuplicateBloodTestCandidate.ValidationStatus) -> (Color, String) {
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
    
    // MARK: - Validation
    private var hasValidSelections: Bool {
        for group in duplicateGroups {
            if group.selectedCandidateId == nil {
                return false
            }
        }
        return true
    }
    
    // MARK: - Actions
    private func acceptSelected() {
        // Update all groups with the selected IDs from state
        for index in duplicateGroups.indices {
            if let selectedId = selectedIds[duplicateGroups[index].id] {
                duplicateGroups[index].selectedCandidateId = selectedId
            } else if duplicateGroups[index].selectedCandidateId == nil {
                // If no selection was made, use the recommended one
                duplicateGroups[index].selectedCandidateId = duplicateGroups[index].recommendedCandidate?.id
            }
        }
        onComplete(duplicateGroups)
        dismiss()
    }
    
    private func acceptAllRecommended() {
        // Update selectedIds state with all recommended candidates
        for group in duplicateGroups {
            if let recommended = group.recommendedCandidate {
                selectedIds[group.id] = recommended.id
            } else if let firstValid = group.candidates.first(where: { $0.validationStatus == .valid }) {
                selectedIds[group.id] = firstValid.id
            }
        }
        acceptSelected()
    }
}

