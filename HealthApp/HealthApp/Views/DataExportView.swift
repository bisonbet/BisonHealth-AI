import SwiftUI

struct DataExportView: View {
    @State private var selectedFormat: ExportFormat = .json
    @State private var includePersonalInfo = true
    @State private var includeBloodTests = true
    @State private var includeChatHistory = false
    @State private var includeDocuments = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @StateObject private var documentExporter = DocumentExporter(
        fileSystemManager: FileSystemManager.shared,
        databaseManager: DatabaseManager.shared
    )
    
    var body: some View {
        Form {
            Section("Export Format") {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        HStack {
                            Image(systemName: format.icon)
                            Text(format.displayName)
                        }
                        .tag(format)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section("Data to Include") {
                Toggle("Personal Information", isOn: $includePersonalInfo)
                Toggle("Blood Test Results", isOn: $includeBloodTests)
                Toggle("Chat History", isOn: $includeChatHistory)
                Toggle("Document Metadata", isOn: $includeDocuments)
            }
            
            Section("Export Options") {
                Button(action: exportData) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        Text(isExporting ? "Exporting..." : "Export Data")
                    }
                }
                .disabled(isExporting || !hasDataToExport)
                
                if isExporting && exportProgress > 0 {
                    ProgressView("Exporting...", value: exportProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            
            if !hasDataToExport {
                Section {
                    Text("Please select at least one data type to export")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Export Health Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(documentExporter.$exportProgress) { progress in
            exportProgress = progress
        }
    }
    
    private var hasDataToExport: Bool {
        includePersonalInfo || includeBloodTests || includeChatHistory || includeDocuments
    }
    
    private func exportData() {
        isExporting = true
        exportProgress = 0.0
        
        Task {
            do {
                // Build set of health data types to include
                var includeTypes = Set<HealthDataType>()
                if includePersonalInfo {
                    includeTypes.insert(.personalInfo)
                }
                if includeBloodTests {
                    includeTypes.insert(.bloodTest)
                }
                // Chat history and documents are handled separately by the exporter
                
                let exportURL: URL
                switch selectedFormat {
                case .json:
                    exportURL = try await documentExporter.exportHealthDataAsJSON(includeTypes: includeTypes)
                case .pdf:
                    exportURL = try await documentExporter.exportHealthReportAsPDF(includeTypes: includeTypes)
                }
                
                await MainActor.run {
                    exportedFileURL = exportURL
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
}

enum ExportFormat: String, CaseIterable {
    case json = "json"
    case pdf = "pdf"
    
    var displayName: String {
        switch self {
        case .json:
            return "JSON"
        case .pdf:
            return "PDF Report"
        }
    }
    
    var icon: String {
        switch self {
        case .json:
            return "doc.text"
        case .pdf:
            return "doc.richtext"
        }
    }
    
    var fileExtension: String {
        return rawValue
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    NavigationStack {
        DataExportView()
    }
}