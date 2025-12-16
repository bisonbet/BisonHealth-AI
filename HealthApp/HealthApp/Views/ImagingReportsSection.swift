import SwiftUI

struct ImagingReportsSection: View {
    @Binding var imagingReports: [MedicalDocument]
    let onDocumentTap: (MedicalDocument) -> Void
    
    var body: some View {
        Section {
            if imagingReports.isEmpty {
                EmptyImagingReportsView()
            } else {
                ForEach(imagingReports.prefix(2)) { report in
                    NavigationLink {
                        MedicalDocumentDetailView(document: report)
                    } label: {
                        ImagingReportRowView(report: report)
                    }
                }

                if imagingReports.count > 2 {
                    NavigationLink {
                        ImagingReportsListView(reports: $imagingReports, onDocumentTap: onDocumentTap)
                    } label: {
                        HStack {
                            Text("More")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("\(imagingReports.count) total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Imaging Reports", systemImage: "camera.metering.matrix")
                Spacer()
            }
        }
    }
}

struct ImagingReportRowView: View {
    let report: MedicalDocument
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.fileName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let date = report.documentDate {
                        Text(DateFormatter.mediumDate.string(from: date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let processedAt = report.processedAt {
                        Text(DateFormatter.mediumDate.string(from: processedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let provider = report.providerName {
                        Text(provider)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    ProcessingStatusBadge(status: report.processingStatus)
                    
                    if !report.extractedSections.isEmpty {
                        Text("\(report.extractedSections.count) sections")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Show key findings if available
            if let findingsSection = report.section(ofType: "Findings") {
                Text(findingsSection.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if let impressionSection = report.section(ofType: "Impression") {
                Text(impressionSection.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptyImagingReportsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.metering.matrix")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No imaging reports")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Import imaging reports from your documents")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct ImagingReportsListView: View {
    @Binding var reports: [MedicalDocument]
    let onDocumentTap: (MedicalDocument) -> Void
    
    var body: some View {
        List {
            ForEach(reports) { report in
                NavigationLink {
                    MedicalDocumentDetailView(document: report)
                } label: {
                    ImagingReportRowView(report: report)
                }
            }
        }
        .navigationTitle("Imaging Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}

