import SwiftUI

// MARK: - Blood Test Import Review View
struct BloodTestImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var importGroups: [BloodTestImportGroup]
    let onComplete: ([BloodTestImportGroup]) -> Void
    
    @State private var showingAcceptAllConfirmation = false
    @State private var selectedIds: [UUID: UUID?] = [:] // groupId -> candidateId (nil means ignore)
    
    init(importGroups: Binding<[BloodTestImportGroup]>, onComplete: @escaping ([BloodTestImportGroup]) -> Void) {
        self._importGroups = importGroups
        self.onComplete = onComplete
    }
    
    // Convenience initializer for non-binding usage
    init(importGroups: [BloodTestImportGroup], onComplete: @escaping ([BloodTestImportGroup]) -> Void) {
        self._importGroups = Binding(
            get: { importGroups },
            set: { _ in }
        )
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationStack {
            List {
                headerSection
                
                ForEach($importGroups) { $group in
                    Section {
                        testGroupView($group)
                    } header: {
                        HStack {
                            Text(group.standardTestName)
                                .font(.headline)
                            Spacer()
                            // Show 'Ignored' if selectedId is explicitly nil
                            if let groupId = selectedIds[group.id], groupId == nil {
                                Text("Will Ignore")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Initialize selectedIds from groups' selectedCandidateId
                for group in importGroups {
                    selectedIds[group.id] = group.selectedCandidateId
                }
            }
            .navigationTitle("Review Lab Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import Selected") {
                        acceptSelected()
                    }
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
                Text("Review \(importGroups.count) extracted test results")
                    .font(.headline)
                
                Text("Please review values before importing. You can deselect items to ignore them.")
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
    private func testGroupView(_ group: Binding<BloodTestImportGroup>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(group.wrappedValue.candidates) { candidate in
                candidateRow(candidate, group: group)
            }
            
            // "Don't Import" Option
            dontImportRow(group: group)
        }
    }
    
    // MARK: - Don't Import Row
    private func dontImportRow(group: Binding<BloodTestImportGroup>) -> some View {
        let groupId = group.wrappedValue.id
        let currentSelection = selectedIds[groupId] ?? group.wrappedValue.selectedCandidateId
        let isSelected = currentSelection == nil

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
            print("🔘 Don't import tapped for group: \(groupId)")
            // Update state dictionary
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
        let currentSelection = selectedIds[group.wrappedValue.id] ?? group.wrappedValue.selectedCandidateId
        let isSelected = currentSelection == candidate.id
        
        // Check if this candidate is the recommended one (matches the group's recommendedCandidate)
        let isRecommended = group.wrappedValue.recommendedCandidate?.id == candidate.id
        
        // Check if calculated
        let isCalculated = candidate.originalTestName.lowercased().contains("calc")
        
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
                    
                    if isCalculated {
                        Text("Calculated")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
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
        .clipped()
        .onTapGesture {
            print("🔵 Candidate tapped: \(candidate.displayValue)")
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
            if let selectedId = selectedIds[importGroups[index].id] {
                // Can be nil (explicit ignore) or UUID
                importGroups[index].selectedCandidateId = selectedId
            }
            // If not in selectedIds, keep existing selectedCandidateId
        }
        onComplete(importGroups)
        dismiss()
    }
    
    private func acceptAllRecommended() {
        // Update selectedIds state with all recommended candidates
        for group in importGroups {
            if let recommended = group.recommendedCandidate {
                selectedIds[group.id] = recommended.id
            } else if let firstValid = group.candidates.first(where: { $0.validationStatus == .valid }) {
                selectedIds[group.id] = firstValid.id
            }
        }
        acceptSelected()
    }
}