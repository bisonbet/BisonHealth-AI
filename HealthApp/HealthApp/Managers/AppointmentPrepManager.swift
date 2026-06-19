import Foundation
import SwiftUI

// MARK: - Generation Stage
/// Progress of a three-call appointment-prep generation run.
enum PrepGenerationStage: Equatable {
    case idle
    case timeline
    case questions
    case relevantInfo
    case done
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .timeline, .questions, .relevantInfo: return true
        default: return false
        }
    }
}

// MARK: - Appointment Prep Manager
/// Drives the "Prep for Doctor Appointment" feature: persistence, medication
/// prefill from the health record, health-data context assembly, and the
/// three-call LLM generation workflow.
@MainActor
final class AppointmentPrepManager: ObservableObject {

    static let shared = AppointmentPrepManager()

    // MARK: - Published Properties
    @Published var preps: [AppointmentPrep] = []
    @Published var currentPrep: AppointmentPrep?
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var generationStage: PrepGenerationStage = .idle
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private let databaseManager: DatabaseManager
    private let healthDataManager: HealthDataManager
    private let settingsManager: SettingsManager

    // MARK: - Initialization
    init(
        databaseManager: DatabaseManager,
        healthDataManager: HealthDataManager,
        settingsManager: SettingsManager
    ) {
        self.databaseManager = databaseManager
        self.healthDataManager = healthDataManager
        self.settingsManager = settingsManager
    }

    /// Convenience initializer using the shared singletons. Kept separate from
    /// the designated initializer so the `@MainActor` `.shared` references are
    /// resolved in an isolated context (Swift 6 concurrency), not as default
    /// argument values.
    convenience init() {
        self.init(
            databaseManager: .shared,
            healthDataManager: .shared,
            settingsManager: .shared
        )
    }

    // MARK: - Loading

    func loadPreps() async {
        isLoading = true
        defer { isLoading = false }
        do {
            preps = try await databaseManager.fetchAppointmentPreps()
            AppLog.shared.database("Loaded \(preps.count) appointment preps")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.shared.error("Failed to load appointment preps: \(error.localizedDescription)", error: error, category: .database)
        }
    }

    // MARK: - Persistence

    func save(_ prep: AppointmentPrep) async throws {
        try await databaseManager.saveAppointmentPrep(prep)
        if let index = preps.firstIndex(where: { $0.id == prep.id }) {
            preps[index] = prep
        } else {
            preps.append(prep)
        }
        preps.sort { $0.lastModified > $1.lastModified }
    }

    func delete(_ prep: AppointmentPrep) async throws {
        try await databaseManager.deleteAppointmentPrep(prep)
        preps.removeAll { $0.id == prep.id }
        if currentPrep?.id == prep.id { currentPrep = nil }
    }

    // MARK: - Medication Prefill

    /// Builds an editable medication list from the user's existing health record.
    func prefillMedications() -> String {
        guard let info = healthDataManager.personalInfo else { return "" }
        var lines: [String] = []
        for medication in info.medications {
            lines.append(medication.displayText)
        }
        for supplement in info.supplements {
            lines.append("\(supplement.name) - \(supplement.dosage.displayText), \(supplement.frequency.displayName)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Generation

    /// Runs the three-call workflow (timeline → questions → relevant info),
    /// updating `currentPrep`/`generationStage` progressively and persisting the
    /// result. Returns the fully populated prep.
    @discardableResult
    func generate(for input: AppointmentPrep) async -> AppointmentPrep {
        errorMessage = nil
        generationStage = .idle

        var prep = input
        prep.clearGeneratedContent()
        prep.status = .generating
        prep.lastModified = Date()
        currentPrep = prep

        // Validate the appointment-specific inputs.
        let errors = AppointmentPrepProcessor.validateInputs(
            symptoms: prep.symptoms,
            notes: prep.notes,
            medications: prep.medications
        )
        if !errors.isEmpty {
            let message = errors.joined(separator: "\n")
            errorMessage = message
            generationStage = .failed(message)
            prep.status = .draft
            currentPrep = prep
            return prep
        }

        isGenerating = true
        defer { isGenerating = false }

        let client = settingsManager.getAIClient()
        let healthContext = await buildHealthContext(selectedTypes: prep.includedHealthDataTypes)

        do {
            // 1. Timeline
            generationStage = .timeline
            let timelineRaw = try await client.sendMessage(
                composeMessage(AppointmentPrepPrompts.timelinePrompt(
                    symptoms: prep.symptoms, notes: prep.notes, medications: prep.medications)),
                context: healthContext
            ).content
            prep.timeline = AppointmentPrepProcessor.cleanSectionOutput(
                timelineRaw, maxItems: AppointmentPrepProcessor.timelineMaxItems)
            prep.lastModified = Date()
            currentPrep = prep

            // 2. Questions
            generationStage = .questions
            let questionsRaw = try await client.sendMessage(
                composeMessage(AppointmentPrepPrompts.questionsPrompt(
                    symptoms: prep.symptoms, notes: prep.notes, medications: prep.medications)),
                context: healthContext
            ).content
            prep.questions = AppointmentPrepProcessor.cleanSectionOutput(
                questionsRaw, maxItems: AppointmentPrepProcessor.questionsMaxItems)
            prep.lastModified = Date()
            currentPrep = prep

            // 3. Relevant Info (enforce the medical disclaimer suffix)
            generationStage = .relevantInfo
            let infoRaw = try await client.sendMessage(
                composeMessage(AppointmentPrepPrompts.relevantInfoPrompt(
                    symptoms: prep.symptoms, notes: prep.notes, medications: prep.medications)),
                context: healthContext
            ).content
            prep.relevantInfo = AppointmentPrepProcessor.cleanSectionOutput(
                infoRaw,
                maxItems: AppointmentPrepProcessor.relevantInfoMaxItems,
                requiredSuffix: AppointmentPrepPrompts.disclaimerSuffix
            )

            prep.status = .complete
            prep.lastModified = Date()
            currentPrep = prep
            generationStage = .done

            try await save(prep)
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            generationStage = .failed(message)
            // Preserve any partial output that was produced.
            prep.status = prep.hasGeneratedContent ? .complete : .draft
            currentPrep = prep
            if prep.hasGeneratedContent {
                do {
                    try await save(prep)
                } catch {
                    AppLog.shared.error("Failed to save partial appointment prep: \(error.localizedDescription)", error: error, category: .database)
                }
            }
            AppLog.shared.error("Appointment prep generation failed: \(message)", error: error, category: .ai)
        }

        return prep
    }

    // MARK: - Private Helpers

    /// Folds the appointment-prep system prompt into the user message so it is
    /// delivered regardless of how each provider wraps the `context` parameter.
    private func composeMessage(_ sectionPrompt: String) -> String {
        "\(AppointmentPrepPrompts.systemPrompt)\n\n\(sectionPrompt)"
    }

    /// Assembles the JSON health-data context (personal info, labs, documents)
    /// for the selected data types — the same structured format used by AI Chat.
    private func buildHealthContext(selectedTypes: Set<HealthDataType>) async -> String {
        // Ensure the health record is loaded.
        if healthDataManager.personalInfo == nil && healthDataManager.bloodTests.isEmpty {
            await healthDataManager.loadHealthData()
        }

        // Map selected types to document categories for filtering.
        var documentCategories: [DocumentCategory] = []
        for type in selectedTypes {
            documentCategories.append(contentsOf: type.relatedDocumentCategories)
        }

        let categoriesToFilter: [DocumentCategory]?
        if !documentCategories.isEmpty {
            categoriesToFilter = documentCategories
        } else if !selectedTypes.isEmpty {
            categoriesToFilter = []
        } else {
            categoriesToFilter = nil
        }

        var documents: [MedicalDocumentSummary] = []
        do {
            let fetched = try await databaseManager.fetchDocumentsForAIContext(categories: categoriesToFilter)
            documents = fetched.map { MedicalDocumentSummary(from: $0) }
        } catch {
            AppLog.shared.ai("[Prep] Failed to fetch documents for context: \(error.localizedDescription)", level: .warning)
        }

        let limit = AIProviderContextLimits.limit(for: settingsManager.modelPreferences.aiProvider)
        let context = ChatContext(
            personalInfo: selectedTypes.contains(.personalInfo) ? healthDataManager.personalInfo : nil,
            bloodTests: selectedTypes.contains(.bloodTest) ? healthDataManager.bloodTests : [],
            medicalDocuments: documents,
            selectedDataTypes: selectedTypes,
            selectedPersonalInfoCategories: Set(PersonalInfoCategory.allCases),
            maxTokens: limit
        )
        return context.buildContextJSON()
    }
}
