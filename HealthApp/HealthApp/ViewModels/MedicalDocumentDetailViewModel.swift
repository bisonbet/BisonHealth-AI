import Foundation
import SwiftUI

// MARK: - Medical Document Detail View Model
@MainActor
class MedicalDocumentDetailViewModel: ObservableObject {
    @Published var document: MedicalDocument
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

    func deleteDocument() async {
        do {
            try await databaseManager.deleteMedicalDocument(document)
            print("✅ Document deleted successfully")
        } catch {
            print("❌ Failed to delete document: \(error)")
        }
    }

    // MARK: - Private Methods
    private func saveDocument() {
        Task {
            do {
                try await databaseManager.updateMedicalDocument(document)
                print("✅ Document updated successfully")
            } catch {
                print("❌ Failed to update document: \(error)")
            }
        }
    }
}
