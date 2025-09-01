import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last updated: \(Date().formatted(date: .long, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                PrivacySection(
                    title: "Data Storage",
                    content: "All your health data is stored locally on your device. We do not collect, transmit, or store your personal health information on our servers."
                )
                
                PrivacySection(
                    title: "iCloud Backup",
                    content: "When enabled, your data is encrypted and backed up to your personal iCloud account. Only you have access to this data through your Apple ID."
                )
                
                PrivacySection(
                    title: "AI Processing",
                    content: "When using AI features, your health data is sent to your configured AI servers for processing. This data is not stored by the AI service and is only used to generate responses."
                )
                
                PrivacySection(
                    title: "Document Processing",
                    content: "Documents are processed using your configured Docling server to extract health information. Original documents remain on your device."
                )
                
                PrivacySection(
                    title: "No Analytics",
                    content: "We do not collect usage analytics, crash reports, or any other data about how you use the app."
                )
                
                PrivacySection(
                    title: "Your Rights",
                    content: "You have complete control over your data. You can export, delete, or modify your health information at any time through the app."
                )
                
                Text("Contact Us")
                    .font(.headline)
                    .padding(.top)
                
                Text("If you have any questions about this privacy policy, please contact us at privacy@healthapp.com")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}