import SwiftUI

struct DocumentsEmptyStateView: View {
    let supportsDocumentScanning: Bool
    let onScanDocument: () -> Void
    let onImportFile: () -> Void
    let onImportPhotos: () -> Void

    init(
        supportsDocumentScanning: Bool = PlatformCapabilities.supportsDocumentScanning,
        onScanDocument: @escaping () -> Void,
        onImportFile: @escaping () -> Void,
        onImportPhotos: @escaping () -> Void
    ) {
        self.supportsDocumentScanning = supportsDocumentScanning
        self.onScanDocument = onScanDocument
        self.onImportFile = onImportFile
        self.onImportPhotos = onImportPhotos
    }
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(BisonTheme.gold)
                
                VStack(spacing: 8) {
                    Text("No Documents")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Import your health documents to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: 12) {
                if supportsDocumentScanning {
                    ImportOptionButton(
                        title: "Scan Document",
                        subtitle: "Use camera to scan papers",
                        icon: "camera.viewfinder",
                        color: BisonTheme.gold,
                        action: onScanDocument
                    )
                }
                
                ImportOptionButton(
                    title: "Import File",
                    subtitle: "Choose from Files app",
                    icon: "folder",
                    color: .green,
                    action: onImportFile
                )
                
                ImportOptionButton(
                    title: "Import Photos",
                    subtitle: "Select from photo library",
                    icon: "photo.on.rectangle",
                    color: .orange,
                    action: onImportPhotos
                )
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ImportOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(.highlight)
    }
}

#Preview {
    DocumentsEmptyStateView(
        onScanDocument: {},
        onImportFile: {},
        onImportPhotos: {}
    )
}
