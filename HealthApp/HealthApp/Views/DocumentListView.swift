import SwiftUI

struct DocumentListView: View {
    let documents: [HealthDocument]
    @Binding var selectedDocuments: Set<UUID>
    let onDocumentTap: (HealthDocument) -> Void
    
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        List {
            ForEach(documents) { document in
                DocumentRowView(
                    document: document,
                    isSelected: selectedDocuments.contains(document.id),
                    isEditing: editMode?.wrappedValue.isEditing == true,
                    onTap: { onDocumentTap(document) },
                    onToggleSelection: {
                        if selectedDocuments.contains(document.id) {
                            selectedDocuments.remove(document.id)
                        } else {
                            selectedDocuments.insert(document.id)
                        }
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct DocumentRowView: View {
    let document: HealthDocument
    let isSelected: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator (when editing)
            if isEditing {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Document thumbnail
            DocumentThumbnailView(document: document)
            
            // Document info
            VStack(alignment: .leading, spacing: 4) {
                Text(document.fileName)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    ProcessingStatusBadge(status: document.processingStatus)
                    
                    Text(document.fileType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text(document.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(RelativeDateTimeFormatter().localizedString(for: document.importedAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron (when not editing)
            if !isEditing {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                onToggleSelection()
            } else {
                onTap()
            }
        }
        .contextMenu {
            Button("View Details", systemImage: "info.circle") {
                onTap()
            }
            
            Button("Share", systemImage: "square.and.arrow.up") {
                // Share functionality would be handled by parent
            }
            
            Divider()
            
            if document.processingStatus == .pending || document.processingStatus == .failed {
                Button("Process Now", systemImage: "gear") {
                    Task {
                        await DocumentProcessor.shared.addToQueue(document, priority: .urgent)
                    }
                }
            }
            
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task {
                    await DocumentManager.shared.deleteDocument(document)
                }
            }
        }
        .accessibilityLabel("Document: \(document.fileName)")
        .accessibilityValue("Status: \(document.processingStatus.displayName), Size: \(document.formattedFileSize)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DocumentThumbnailView: View {
    let document: HealthDocument
    
    var body: some View {
        Group {
            if let thumbnailPath = document.thumbnailPath,
               let image = UIImage(contentsOfFile: thumbnailPath.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: document.fileType.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .frame(width: 50, height: 50)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .clipped()
    }
}

struct ProcessingStatusBadge: View {
    let status: ProcessingStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.2))
        .foregroundColor(statusColor)
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .queued:
            return .gray
        }
    }
}

#Preview {
    NavigationStack {
        DocumentListView(
            documents: [
                HealthDocument(
                    fileName: "Blood Test Results - January 2024.pdf",
                    fileType: .pdf,
                    filePath: URL(fileURLWithPath: "/tmp/test.pdf"),
                    processingStatus: .completed,
                    fileSize: 1024000
                ),
                HealthDocument(
                    fileName: "X-Ray Report.jpg",
                    fileType: .jpg,
                    filePath: URL(fileURLWithPath: "/tmp/xray.jpg"),
                    processingStatus: .processing,
                    fileSize: 2048000
                ),
                HealthDocument(
                    fileName: "Prescription.png",
                    fileType: .png,
                    filePath: URL(fileURLWithPath: "/tmp/prescription.png"),
                    processingStatus: .failed,
                    fileSize: 512000
                )
            ],
            selectedDocuments: .constant([]),
            onDocumentTap: { _ in }
        )
    }
}