import SwiftUI

struct DataExportView: View {
    @State private var selectedFormat: ExportFormat = .json
    @State private var includePersonalInfo = true
    @State private var includeBloodTests = true
    @State private var includeChatHistory = false
    @State private var includeDocuments = false
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    
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
    }
    
    private var hasDataToExport: Bool {
        includePersonalInfo || includeBloodTests || includeChatHistory || includeDocuments
    }
    
    private func exportData() {
        isExporting = true
        
        Task {
            do {
                // Simulate export process
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Create mock export file
                let fileName = "HealthData_Export_\(Date().formatted(date: .numeric, time: .omitted)).\(selectedFormat.fileExtension)"
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = documentsPath.appendingPathComponent(fileName)
                
                let exportContent = generateExportContent()
                try exportContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                await MainActor.run {
                    exportedFileURL = fileURL
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    print("Export failed: \(error)")
                }
            }
        }
    }
    
    private func generateExportContent() -> String {
        switch selectedFormat {
        case .json:
            return """
            {
              "exportDate": "\(Date().ISO8601Format())",
              "format": "json",
              "version": "1.0",
              "data": {
                "personalInfo": \(includePersonalInfo ? "{ \"placeholder\": true }" : "null"),
                "bloodTests": \(includeBloodTests ? "[]" : "null"),
                "chatHistory": \(includeChatHistory ? "[]" : "null"),
                "documents": \(includeDocuments ? "[]" : "null")
              }
            }
            """
        case .pdf:
            return """
            Health Data Export Report
            Generated: \(Date().formatted())
            
            This is a placeholder PDF export.
            In a real implementation, this would contain formatted health data.
            """
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