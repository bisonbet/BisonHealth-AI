import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last updated: October 25, 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                PrivacySection(
                    title: "No Data Collection by BisonHealth AI",
                    content: "BisonHealth AI does not collect, sell, rent, share, or monetize your personal information, health information, documents, chats, usage activity, analytics, crash reports, device identifiers, or advertising identifiers. We do not operate a server account for your app data, and we do not receive your health data unless you choose to send it to us outside the app for support."
                )

                PrivacySection(
                    title: "Local Storage",
                    content: """
                    Your health data, documents, extracted information, chat history, appointment prep records, settings, and generated content are stored on your device. The app does not sync your records through CloudKit.

                    Encrypted on this device: health records, imported document files, the page previews made from them, document tags and notes, extracted text, chat history, and appointment prep records.

                    Not encrypted: documents imported before 25 October 2026 kept a copy of their original file name in their stored file name, so a name like "Lab_Results_March.pdf" can still appear in a file listing or a device backup. The file's contents were always encrypted. Documents imported after that date are stored under a random name instead.

                    Data leaves your device in these cases, and only these:

                    • An AI provider you configure. If you select AWS Bedrock or an OpenAI-compatible server, your message and the health data you selected as context are sent to it. The chat screen shows which provider is in use before you send, and asks you once before the first such message. The on-device model sends nothing.

                    • Your encryption key, through iCloud Keychain. The key that unlocks your database is stored so that it can be restored along with your device. Without this, a restored device could not read its own data. The key syncs; your records do not.

                    • Device backups. Your encrypted database is included in normal iPhone backups, in encrypted form.

                    • Downloading an on-device model contacts Hugging Face to fetch the model files. No health data is sent. Loading a model you have already downloaded needs no network at all.

                    • Opening a genetics reference link sends that gene and result to an external site so it can show matching guidance. The app asks first.

                    • Anything you explicitly export or share.

                    The app contains no analytics, tracking, or crash-reporting services.
                    """
                )

                PrivacySection(
                    title: "Apple Health",
                    content: """
                    If you grant permission, the app reads from Apple Health so your own records are filled in for you. It reads only, and only these: date of birth, biological sex, blood type, height, body mass, heart rate, blood pressure, body temperature, respiratory rate, blood oxygen, and sleep analysis.

                    The app never writes anything to Apple Health, and it asks Apple for no permission to do so. What it reads is stored on this device like any other health record, and leaves the device only in the cases listed above. You can withdraw access at any time in the Health app, under Sharing.
                    """
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
                    content: "Because your app data is stored locally, you can view, edit, export, or delete it through the app and your device controls. Reset Database in Settings removes your health records, imported document files and their page previews, and your chat history from this device, and keeps no backup of them. If you delete the app or erase your device data, locally stored app information may be deleted according to iOS behavior and your backup settings."
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
