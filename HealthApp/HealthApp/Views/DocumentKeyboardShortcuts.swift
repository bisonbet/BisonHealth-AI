import SwiftUI

// MARK: - Document Keyboard Shortcuts
struct DocumentKeyboardShortcuts: ViewModifier {
    let documentManager: DocumentManager
    let onScanDocument: () -> Void
    let onImportFile: () -> Void
    let onShowFilter: () -> Void
    let onShowBatchProcessing: () -> Void
    
    func body(content: Content) -> some View {
        content
            .modifier(BasicKeyboardShortcuts(
                onScanDocument: onScanDocument,
                onImportFile: onImportFile,
                onShowFilter: onShowFilter
            ))
            .modifier(SelectionKeyboardShortcuts(
                documentManager: documentManager
            ))
            .modifier(ProcessingKeyboardShortcuts(
                documentManager: documentManager,
                onShowBatchProcessing: onShowBatchProcessing
            ))
    }
}

// MARK: - Separate Keyboard Shortcut Modifiers

struct BasicKeyboardShortcuts: ViewModifier {
    let onScanDocument: () -> Void
    let onImportFile: () -> Void
    let onShowFilter: () -> Void
    
    func body(content: Content) -> some View {
        content
            // Note: These shortcuts would need to be attached to specific buttons
            // in the actual UI rather than globally here
    }
}

struct SelectionKeyboardShortcuts: ViewModifier {
    let documentManager: DocumentManager
    
    func body(content: Content) -> some View {
        content
            // Note: Selection shortcuts would be handled by the parent view
    }
}

struct ProcessingKeyboardShortcuts: ViewModifier {
    let documentManager: DocumentManager
    let onShowBatchProcessing: () -> Void
    
    func body(content: Content) -> some View {
        content
            // Note: Processing shortcuts would be handled by the parent view
    }
}

extension View {
    func documentKeyboardShortcuts(
        documentManager: DocumentManager,
        onScanDocument: @escaping () -> Void,
        onImportFile: @escaping () -> Void,
        onShowFilter: @escaping () -> Void,
        onShowBatchProcessing: @escaping () -> Void
    ) -> some View {
        modifier(DocumentKeyboardShortcuts(
            documentManager: documentManager,
            onScanDocument: onScanDocument,
            onImportFile: onImportFile,
            onShowFilter: onShowFilter,
            onShowBatchProcessing: onShowBatchProcessing
        ))
    }
}

// MARK: - Document Accessibility
struct DocumentAccessibilityModifier: ViewModifier {
    let document: HealthDocument
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(documentAccessibilityLabel)
            .accessibilityValue(documentAccessibilityValue)
            .accessibilityHint(documentAccessibilityHint)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var documentAccessibilityLabel: String {
        var components: [String] = []
        
        components.append(document.fileName)
        components.append(document.fileType.displayName)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        components.append("Imported \(formatter.string(from: document.importedAt))")
        
        return components.joined(separator: ", ")
    }
    
    private var documentAccessibilityValue: String {
        var components: [String] = []
        
        components.append(document.processingStatus.displayName)
        
        if document.fileSize > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            components.append(formatter.string(fromByteCount: document.fileSize))
        }
        
        return components.joined(separator: ", ")
    }
    
    private var documentAccessibilityHint: String {
        if isSelected {
            return "Double tap to deselect"
        } else {
            return "Double tap to select and view details"
        }
    }
}

extension View {
    func documentAccessibility(document: HealthDocument, isSelected: Bool) -> some View {
        modifier(DocumentAccessibilityModifier(document: document, isSelected: isSelected))
    }
}