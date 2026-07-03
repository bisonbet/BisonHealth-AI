import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last updated: July 3, 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                PrivacySection(
                    title: "No Data Collection by BisonHealth AI",
                    content: "BisonHealth AI does not collect, sell, rent, share, or monetize your personal information, health information, documents, chats, usage activity, analytics, crash reports, device identifiers, or advertising identifiers. We do not operate a server account for your app data, and we do not receive your health data unless you choose to send it to us outside the app for support."
                )

                PrivacySection(
                    title: "Local Storage",
                    content: "Your health data, documents, extracted information, chat history, appointment prep records, settings, and generated content are stored on your device. The app encrypts health data, documents, chats, and appointment prep records. iCloud/CloudKit backup is not used by the app. Data leaves your device only when you take an action such as exporting, sharing, backing up through your own device settings, or configuring an external AI provider."
                )

                PrivacySection(
                    title: "AI Processing",
                    content: "If you configure an external AI provider, the information needed for that request may be sent from your device to the provider you selected. That provider is independent from BisonHealth AI and is governed by its own privacy policy, security practices, retention terms, and account settings. On-device AI features, when available and selected, process locally instead."
                )
                
                PrivacySection(
                    title: "Document Processing",
                    content: "Documents are processed locally where possible using device frameworks and app logic. If you enable a cloud AI extraction provider, extracted text may be sent to that configured provider. If you additionally enable an optional image-sending setting, images of document pages may be sent to that provider during extraction. These cloud options require your configuration or opt-in."
                )
                
                PrivacySection(
                    title: "No Analytics",
                    content: "We do not collect usage analytics, telemetry, tracking data, crash reports, or behavioral data about how you use the app. Any Analytics setting shown in the app is a disabled future feature unless a later version clearly explains the behavior and asks for consent."
                )

                PrivacySection(
                    title: "Not HIPAA Compliant",
                    content: "\(BisonHealthLegalCopy.notForProfessionalUse) \(BisonHealthLegalCopy.noHIPAAGuarantee)"
                )

                PrivacySection(
                    title: "Personal Health Data Only",
                    content: "Use the app only for your own personal health information or information you have a lawful right to manage for personal purposes. Do not use the app to process patient records, client records, employee health data, or other regulated data on behalf of an organization."
                )

                PrivacySection(
                    title: "User-Controlled Exports and Sharing",
                    content: "You control exports and sharing from your device. Once you export, copy, share, upload, or send information to another app, person, service, AI provider, cloud storage location, or communication channel, that destination controls what happens next. Review the destination's privacy and security practices before sharing health information."
                )
                
                PrivacySection(
                    title: "Your Rights",
                    content: "Because your app data is stored locally, you can view, edit, export, or delete it through the app and your device controls. If you delete the app or erase your device data, locally stored app information may be deleted according to iOS behavior and your backup settings."
                )
                
                Text("Contact Us")
                    .font(.headline)
                    .padding(.top)
                
                Text("If you have any questions about this privacy policy, please contact us at support@bisonnetworking.com")
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
