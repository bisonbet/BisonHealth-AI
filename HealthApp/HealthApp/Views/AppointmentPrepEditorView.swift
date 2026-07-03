import SwiftUI

// MARK: - Appointment Prep Editor View
/// Collects this visit's inputs, runs the three-call generation workflow with
/// progressive feedback, and shows the resulting report.
struct AppointmentPrepEditorView: View {
    @ObservedObject var manager: AppointmentPrepManager
    @Environment(\.dismiss) private var dismiss

    private let existingPrep: AppointmentPrep?
    private let onComplete: ((AppointmentPrep) -> Void)?

    @State private var prep: AppointmentPrep
    @State private var hasDate: Bool
    @State private var validationErrors: [String] = []
    @State private var didPrefill = false

    init(
        manager: AppointmentPrepManager,
        existingPrep: AppointmentPrep? = nil,
        onComplete: ((AppointmentPrep) -> Void)? = nil
    ) {
        self.manager = manager
        self.existingPrep = existingPrep
        self.onComplete = onComplete
        let initial = existingPrep ?? AppointmentPrep()
        _prep = State(initialValue: initial)
        _hasDate = State(initialValue: initial.appointmentDate != nil)
    }

    private var isNew: Bool { existingPrep == nil }

    /// Prefer the manager's live copy (progressive output) when it matches this prep.
    private var displayPrep: AppointmentPrep {
        if let current = manager.currentPrep, current.id == prep.id { return current }
        return prep
    }

    private var showsReport: Bool {
        manager.generationStage.isRunning || displayPrep.hasGeneratedContent
    }

    var body: some View {
        NavigationStack {
            Form {
                visitSection
                medicationsSection
                detailsSection
                contextSection
                generateSection

                if showsReport {
                    reportSection
                }
            }
            .navigationTitle(isNew ? "New Appointment Prep" : "Edit Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(manager.isGenerating)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if manager.generationStage == .done {
                        Button("Done") {
                            onComplete?(displayPrep)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("prep.editor.done")
                    }
                }
            }
            .onAppear(perform: prefillIfNeeded)
        }
    }

    // MARK: - Input Sections

    private var visitSection: some View {
        Section("This Visit") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Symptoms / Concerns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $prep.symptoms)
                    .frame(minHeight: 110)
                    .accessibilityLabel("Symptoms or concerns")
                    .accessibilityIdentifier("prep.editor.symptoms")
                if prep.symptoms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Describe what you're experiencing, when it started, and how it has changed.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Additional Notes (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $prep.notes)
                    .frame(minHeight: 70)
                    .accessibilityLabel("Additional notes")
                    .accessibilityIdentifier("prep.editor.notes")
            }
        }
    }

    private var medicationsSection: some View {
        Section {
            TextEditor(text: $prep.medications)
                .frame(minHeight: 90)
                .accessibilityLabel("Current medications")
                .accessibilityIdentifier("prep.editor.medications")
        } header: {
            Text("Current Medications")
        } footer: {
            Text("Pre-filled from your health record. Edit as needed — one per line.")
        }
    }

    private var detailsSection: some View {
        Section("Appointment Details (optional)") {
            TextField("Title", text: $prep.title)
                .accessibilityIdentifier("prep.editor.title")
            TextField("Provider / Clinic", text: Binding(
                get: { prep.providerName ?? "" },
                set: { prep.providerName = $0.isEmpty ? nil : $0 }
            ))
            Toggle("Set appointment date", isOn: $hasDate)
            if hasDate {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { prep.appointmentDate ?? Date() },
                        set: { prep.appointmentDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        }
        .onChange(of: hasDate) { _, newValue in
            if !newValue { prep.appointmentDate = nil }
            else if prep.appointmentDate == nil { prep.appointmentDate = Date() }
        }
    }

    private var contextSection: some View {
        Section {
            ForEach(HealthDataType.allCases, id: \.self) { type in
                Toggle(isOn: Binding(
                    get: { prep.includedHealthDataTypes.contains(type) },
                    set: { isOn in
                        if isOn { prep.includedHealthDataTypes.insert(type) }
                        else { prep.includedHealthDataTypes.remove(type) }
                    }
                )) {
                    Label(type.displayName, systemImage: type.icon)
                }
            }
        } header: {
            Text("Include From My Record")
        } footer: {
            Text("These records are shared with the AI to tailor your prep.")
        }
    }

    private var generateSection: some View {
        Section {
            if !validationErrors.isEmpty {
                ForEach(validationErrors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let error = manager.errorMessage, manager.generationStage.isFailedState {
                Label(error, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button(action: runGeneration) {
                HStack {
                    Spacer()
                    if manager.isGenerating {
                        ProgressView().controlSize(.small)
                        Text(generatingLabel)
                    } else {
                        Image(systemName: "sparkles")
                        Text(displayPrep.hasGeneratedContent ? "Regenerate Report" : "Generate Prep Report")
                    }
                    Spacer()
                }
            }
            .disabled(manager.isGenerating)
            .accessibilityIdentifier("prep.editor.generate")
        }
    }

    private var generatingLabel: String {
        switch manager.generationStage {
        case .timeline: return "Building timeline…"
        case .questions: return "Drafting questions…"
        case .relevantInfo: return "Gathering relevant info…"
        default: return "Generating…"
        }
    }

    // MARK: - Report Section

    private var reportSection: some View {
        Section("Report") {
            PrepSectionCard(
                title: "Timeline",
                systemImage: "clock.arrow.circlepath",
                accent: BisonTheme.sage,
                content: .constant(displayPrep.timeline),
                isLoading: manager.generationStage == .timeline
            )
            PrepSectionCard(
                title: "Questions for the Doctor",
                systemImage: "questionmark.bubble",
                accent: BisonTheme.gold,
                content: .constant(displayPrep.questions),
                isLoading: manager.generationStage == .questions
            )
            PrepSectionCard(
                title: "Relevant Info",
                systemImage: "info.circle",
                accent: BisonTheme.steel,
                content: .constant(displayPrep.relevantInfo),
                isLoading: manager.generationStage == .relevantInfo
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        if isNew && prep.medications.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prep.medications = manager.prefillMedications()
        }
    }

    private func runGeneration() {
        let errors = AppointmentPrepProcessor.validateInputs(
            symptoms: prep.symptoms, notes: prep.notes, medications: prep.medications)
        guard errors.isEmpty else {
            validationErrors = errors
            return
        }
        validationErrors = []
        Task {
            let result = await manager.generate(for: prep)
            prep = result
        }
    }
}

// MARK: - Generation Stage Helpers
extension PrepGenerationStage {
    var isFailedState: Bool {
        if case .failed = self { return true }
        return false
    }
}
