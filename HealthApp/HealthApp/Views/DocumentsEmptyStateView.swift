import SwiftUI

struct DocumentsEmptyStateView: View {
    let supportsDocumentScanning: Bool
    /// The list is empty because the load failed, not because nothing was ever imported.
    /// Telling someone they have no documents when their records are there but unreadable
    /// is the worst possible reading of this screen.
    let didFailToLoad: Bool
    let onScanDocument: () -> Void
    let onImportFile: () -> Void
    let onImportPhotos: () -> Void
    let onRetry: (() -> Void)?

    init(
        supportsDocumentScanning: Bool = PlatformCapabilities.supportsDocumentScanning,
        didFailToLoad: Bool = false,
        onScanDocument: @escaping () -> Void,
        onImportFile: @escaping () -> Void,
        onImportPhotos: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.supportsDocumentScanning = supportsDocumentScanning
        self.didFailToLoad = didFailToLoad
        self.onScanDocument = onScanDocument
        self.onImportFile = onImportFile
        self.onImportPhotos = onImportPhotos
        self.onRetry = onRetry
    }
    
    var body: some View {
        if didFailToLoad {
            loadFailureState
        } else {
            emptyLibraryState
        }
    }

    private var loadFailureState: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Couldn't Load Your Documents")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Your documents are still on this device — they just could not be read right now. Nothing has been deleted.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let onRetry {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("documentsRetryLoadButton")
            }
        }
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documentsLoadFailedState")
    }

    private var emptyLibraryState: some View {
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
