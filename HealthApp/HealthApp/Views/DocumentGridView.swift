import SwiftUI

struct DocumentGridView: View {
    let documents: [MedicalDocument]
    @Binding var selectedDocuments: Set<UUID>
    let onDocumentTap: (MedicalDocument) -> Void
    
    @Environment(\.editMode) private var editMode
    /// One adaptive column rather than a fixed count.
    ///
    /// This used to be a hardcoded 4 columns on any regular-width device, holding tiles with
    /// a fixed 200 pt frame. The arithmetic does not work: an 11-inch iPad in portrait is
    /// 834 pt, so after the grid's padding and spacing each column is 188 pt and every tile
    /// overflowed by 12 pt — they overlapped, and the first one clipped. In Split View the
    /// column drops to around 80 pt and the layout collapses completely.
    ///
    /// `.adaptive` lets the column count follow the available width, so there is no width to
    /// get wrong: Split View, Slide Over, portrait, landscape and a phone all work from the
    /// same rule, and the tile fills whatever column it is given.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Self.minimumTileWidth, maximum: Self.maximumTileWidth), spacing: 16)]
    }

    /// Below this a tile cannot show a readable filename; above it the thumbnails get
    /// gratuitously large on a 13-inch landscape.
    static let minimumTileWidth: CGFloat = 150
    static let maximumTileWidth: CGFloat = 220
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(documents) { document in
                    DocumentGridItem(
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
            .padding()
        }
    }
}

struct DocumentGridItem: View {
    let document: MedicalDocument
    let isSelected: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    
    
    /// The thumbnail's shape, not its size. The tile takes whatever width its column gives
    /// it — a fixed size inside a flexible column is what made tiles overlap.
    private static let thumbnailAspectRatio: CGFloat = 4.0 / 3.0
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Document thumbnail
                documentThumbnail
                
                // Selection indicator (when editing)
                if isEditing {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? BisonTheme.inkOnGold : .secondary)
                            .background(isSelected ? BisonTheme.gold : Color.white)
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
                
                // Processing indicator
                if document.processingStatus == .processing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(Self.thumbnailAspectRatio, contentMode: .fit)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? BisonTheme.gold : Color.clear, lineWidth: 3)
            )
            
            // Document info
            VStack(spacing: 4) {
                Text(document.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 4) {
                    ProcessingStatusIndicator(status: document.processingStatus)
                    
                    Text(document.fileType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(document.formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
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
        .hoverEffect(.highlight)
        .accessibilityLabel("Document: \(document.fileName)")
        .accessibilityValue("Status: \(document.processingStatus.displayName), Size: \(document.formattedFileSize)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .scaleEffect(isSelected ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private var documentThumbnail: some View {
        Group {
            if let thumbnailPath = document.thumbnailPath,
               let image = FileSystemManager.shared.loadThumbnailData(at: thumbnailPath).flatMap(UIImage.init(data:)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: document.fileType.icon)
                        .font(.system(size: 32))
                        .foregroundColor(BisonTheme.gold)
                    
                    Text(document.fileType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct ProcessingStatusIndicator: View {
    let status: ProcessingStatus
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .processing:
            return BisonTheme.gold
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
        DocumentGridView(
            documents: [
                MedicalDocument(
                    fileName: "Blood Test Results - January 2024.pdf",
                    fileType: .pdf,
                    filePath: URL(fileURLWithPath: "/tmp/test.pdf"),
                    processingStatus: .completed,
                    fileSize: 1024000
                ),
                MedicalDocument(
                    fileName: "X-Ray Report.jpg",
                    fileType: .jpg,
                    filePath: URL(fileURLWithPath: "/tmp/xray.jpg"),
                    processingStatus: .processing,
                    fileSize: 2048000
                ),
                MedicalDocument(
                    fileName: "Prescription.png",
                    fileType: .png,
                    filePath: URL(fileURLWithPath: "/tmp/prescription.png"),
                    processingStatus: .failed,
                    fileSize: 512000
                ),
                MedicalDocument(
                    fileName: "Lab Results March.pdf",
                    fileType: .pdf,
                    filePath: URL(fileURLWithPath: "/tmp/lab.pdf"),
                    processingStatus: .pending,
                    fileSize: 756000
                ),
                MedicalDocument(
                    fileName: "Insurance Card.jpg",
                    fileType: .jpg,
                    filePath: URL(fileURLWithPath: "/tmp/insurance.jpg"),
                    processingStatus: .completed,
                    fileSize: 1200000
                ),
                MedicalDocument(
                    fileName: "Vaccination Record.pdf",
                    fileType: .pdf,
                    filePath: URL(fileURLWithPath: "/tmp/vaccine.pdf"),
                    processingStatus: .queued,
                    fileSize: 890000
                )
            ],
            selectedDocuments: .constant([]),
            onDocumentTap: { _ in }
        )
    }
}
