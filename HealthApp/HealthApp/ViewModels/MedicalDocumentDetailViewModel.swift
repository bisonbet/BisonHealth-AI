import Foundation
import SwiftUI

// MARK: - Medical Document Detail View Model
@MainActor
class MedicalDocumentDetailViewModel: ObservableObject {
    @Published var document: MedicalDocument
    @Published var deleteErrorMessage: String?
    private let databaseManager = DatabaseManager.shared

    init(document: MedicalDocument) {
        self.document = document
    }

    // MARK: - Update Methods
    func updateDocumentDate(_ date: Date) {
        document.documentDate = date
        document.lastEditedAt = Date()
        saveDocument()
    }

    func updateCategory(_ category: DocumentCategory) {
        document.documentCategory = category
        document.lastEditedAt = Date()
        saveDocument()
    }

    func updateProviderName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        document.providerName = trimmed.isEmpty ? nil : trimmed
        document.lastEditedAt = Date()
        saveDocument()
    }

    func updateProviderType(_ type: ProviderType) {
        document.providerType = type
        document.lastEditedAt = Date()
        saveDocument()
    }

    func toggleAIContext(_ enabled: Bool) {
        document.includeInAIContext = enabled
        saveDocument()
    }

    func updatePriority(_ priority: Int) {
        document.contextPriority = priority
        saveDocument()
    }

    func updateSection(_ section: DocumentSection) {
        document.updateSection(section)
        document.lastEditedAt = Date()
        saveDocument()
    }

    func deleteSection(_ id: UUID) {
        document.removeSection(id: id)
        document.lastEditedAt = Date()
        saveDocument()
    }

    func updateTags(_ tags: [String]) {
        document.tags = tags
        saveDocument()
    }

    func updateNotes(_ notes: String) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        document.notes = trimmed.isEmpty ? nil : trimmed
        document.lastEditedAt = Date()
        saveDocument()
    }

    /// Returns whether the document was actually removed, so the caller can keep the
    /// detail view on screen and surface the failure instead of dismissing regardless.
    @discardableResult
    func deleteDocument() async -> Bool {
        guard await DocumentManager.shared.deleteDocument(document) else {
            AppLog.shared.documents("Failed to delete document '\(document.fileName)'", level: .error)
            deleteErrorMessage = "The document could not be deleted. Please try again."
            return false
        }

        AppLog.shared.documents("Document deleted successfully")
        return true
    }

    // MARK: - Private Methods
    private func saveDocument() {
        Task {
            do {
                try await databaseManager.updateMedicalDocument(document)
                AppLog.shared.documents("Document updated successfully")
            } catch {
                AppLog.shared.documents("Failed to update document: \(error)", level: .error)
            }
        }
    }
}
