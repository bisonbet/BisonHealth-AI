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
                    content: "All your health data is stored locally on your device. We do not collect, transmit, or store your personal health information on our servers. iCloud/CloudKit backup is not used; data does not leave your device unless you explicitly export it."
                )

                PrivacySection(
                    title: "AI Processing",
                    content: "When using AI features, your health data is sent to your configured AI servers for processing. This data is not stored by the AI service and is only used to generate responses."
                )
                
                PrivacySection(
                    title: "Document Processing",
                    content: "Documents are processed entirely on your device using Apple's PDFKit and Vision frameworks to extract health information. Original documents remain on your device. If you enable a cloud AI extraction provider, extracted text may be sent to that provider to improve accuracy. If you additionally enable the optional \"Send page images\" setting, images of your document pages are sent to that provider during extraction — this is off by default and requires your explicit opt-in."
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