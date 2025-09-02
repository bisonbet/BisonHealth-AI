import SwiftUI

struct BatchProcessingView: View {
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var documentProcessor: DocumentProcessor
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPriority: ProcessingPriority = .normal
    @State private var showingConfirmation = false
    
    private var selectedDocuments: [HealthDocument] {
        documentManager.documents.filter { documentManager.selectedDocuments.contains($0.id) }
    }
    
    private var pendingDocuments: [HealthDocument] {
        selectedDocuments.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Selected Documents
                selectedDocumentsSection
                
                // Processing Options
                processingOptionsSection
                
                // Current Queue Status
                queueStatusSection
                
                Spacer()
                
                // Action Buttons
                actionButtonsSection
            }
            .padding()
            .navigationTitle("Batch Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Start Batch Processing", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Process") {
                Task {
                    await startBatchProcessing()
                    dismiss()
                }
            }
        } message: {
            Text("Process \(pendingDocuments.count) documents with \(selectedPriority.displayName) priority?")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("Batch Processing")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Process multiple documents at once")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Selected Documents Section
    
    private var selectedDocumentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Documents (\(selectedDocuments.count))")
                .font(.headline)
            
            if selectedDocuments.isEmpty {
                Text("No documents selected")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(selectedDocuments) { document in
                            BatchDocumentRow(document: document)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Processing Options Section
    
    private var processingOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Options")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Priority Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Priority")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Priority", selection: $selectedPriority) {
                        ForEach(ProcessingPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Processing Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processing Information")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    InfoItem(
                        label: "Documents to process",
                        value: "\(pendingDocuments.count) of \(selectedDocuments.count)"
                    )
                    
                    InfoItem(
                        label: "Already processed",
                        value: "\(selectedDocuments.count - pendingDocuments.count)"
                    )
                    
                    InfoItem(
                        label: "Estimated time",
                        value: estimatedProcessingTime
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Queue Status Section
    
    private var queueStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Queue Status")
                .font(.headline)
            
            VStack(spacing: 8) {
                if documentProcessor.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text("Processing in progress...")
                            .font(.subheadline)
                        
                        Spacer()
                    }
                }
                
                InfoItem(
                    label: "Documents in queue",
                    value: "\(documentProcessor.processingQueue.count)"
                )
                
                InfoItem(
                    label: "Processing progress",
                    value: "\(Int(documentProcessor.processingProgress * 100))%"
                )
                
                if !documentProcessor.processingErrors.isEmpty {
                    InfoItem(
                        label: "Recent errors",
                        value: "\(documentProcessor.processingErrors.count)",
                        color: .red
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button("Start Processing") {
                showingConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(pendingDocuments.isEmpty)
            
            HStack(spacing: 12) {
                Button("Pause Queue") {
                    documentProcessor.pauseProcessing()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(!documentProcessor.isProcessing)
                
                Button("Clear Queue") {
                    Task {
                        await documentProcessor.clearQueue()
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(documentProcessor.processingQueue.isEmpty)
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var estimatedProcessingTime: String {
        let documentCount = pendingDocuments.count
        let estimatedMinutes = documentCount * 2 // Rough estimate: 2 minutes per document
        
        if estimatedMinutes < 60 {
            return "\(estimatedMinutes) minutes"
        } else {
            let hours = estimatedMinutes / 60
            let minutes = estimatedMinutes % 60
            return "\(hours)h \(minutes)m"
        }
    }
    
    // MARK: - Actions
    
    private func startBatchProcessing() async {
        await documentProcessor.processBatch(pendingDocuments, priority: selectedPriority)
    }
}

// MARK: - Supporting Views

struct BatchDocumentRow: View {
    let document: HealthDocument
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnailPath = document.thumbnailPath,
                   let image = UIImage(contentsOfFile: thumbnailPath.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: document.fileType.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(.systemGray5))
            .cornerRadius(6)
            .clipped()
            
            // Document info
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    ProcessingStatusBadge(status: document.processingStatus)
                    
                    Text(document.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Processing indicator
            if document.processingStatus == .pending || document.processingStatus == .failed {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if document.processingStatus == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct InfoItem: View {
    let label: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

#Preview {
    BatchProcessingView(
        documentManager: DocumentManager.shared,
        documentProcessor: DocumentProcessor.shared
    )
}