import SwiftUI

struct HealthCheckupsSection: View {
    @Binding var healthCheckups: [MedicalDocument]
    let onDocumentTap: (MedicalDocument) -> Void
    
    var body: some View {
        Section {
            if healthCheckups.isEmpty {
                EmptyHealthCheckupsView()
            } else {
                ForEach(healthCheckups.prefix(3)) { checkup in
                    NavigationLink {
                        MedicalDocumentDetailView(document: checkup)
                    } label: {
                        HealthCheckupRowView(checkup: checkup)
                    }
                }
                
                if healthCheckups.count > 3 {
                    NavigationLink("View All (\(healthCheckups.count))") {
                        HealthCheckupsListView(checkups: $healthCheckups, onDocumentTap: onDocumentTap)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        } header: {
            HStack {
                Label("Medical Visits", systemImage: "doc.text")
                Spacer()
            }
        }
    }
}

struct HealthCheckupRowView: View {
    let checkup: MedicalDocument
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkup.fileName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let date = checkup.documentDate {
                        Text(DateFormatter.mediumDate.string(from: date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let processedAt = checkup.processedAt {
                        Text(DateFormatter.mediumDate.string(from: processedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let provider = checkup.providerName {
                        Text(provider)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    ProcessingStatusBadge(status: checkup.processingStatus)
                    
                    if !checkup.extractedSections.isEmpty {
                        Text("\(checkup.extractedSections.count) sections")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Show assessment or plan if available
            if let assessmentSection = checkup.section(ofType: "Assessment") {
                Text(assessmentSection.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if let planSection = checkup.section(ofType: "Plan") {
                Text(planSection.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmptyHealthCheckupsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No medical visits")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Import doctor's notes, specialist visits, and procedure reports from your documents")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct HealthCheckupsListView: View {
    @Binding var checkups: [MedicalDocument]
    let onDocumentTap: (MedicalDocument) -> Void
    
    var body: some View {
        List {
            ForEach(checkups) { checkup in
                NavigationLink {
                    MedicalDocumentDetailView(document: checkup)
                } label: {
                    HealthCheckupRowView(checkup: checkup)
                }
            }
        }
        .navigationTitle("Medical Visits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

