import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Last updated: July 3, 2026")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TermsSectionView(
                            title: "Acceptance of Terms",
                            content: "By downloading, accessing, or using BisonHealth AI, you agree to these Terms of Service and the Privacy Policy. If you do not agree, do not use the app."
                        )
                        
                        TermsSectionView(
                            title: "Description of Service",
                            content: "BisonHealth AI is a personal health organization app that helps individuals store, review, summarize, and prepare questions about their own health information. The app is intended for personal informational use only and is not a healthcare service, medical device, provider portal, patient record system, or emergency tool."
                        )

                        TermsSectionView(
                            title: "Personal Use Only",
                            content: "You may use the app only for your own personal health information or information you have a lawful right to manage for personal purposes. \(BisonHealthLegalCopy.notForProfessionalUse)"
                        )

                        TermsSectionView(
                            title: "Not HIPAA Compliant",
                            content: "BisonHealth AI is not designed for HIPAA-regulated use and does not provide HIPAA compliance. We are not acting as a Business Associate, do not enter into Business Associate Agreements (BAAs), and do not provide HIPAA-required administrative, physical, technical, audit, access-control, retention, or breach-response commitments. Do not use the app to process Protected Health Information on behalf of a covered entity or business associate."
                        )
                        
                        TermsSectionView(
                            title: "User Responsibilities",
                            content: "\(BisonHealthLegalCopy.userResponsibility) You are responsible for securing your device, passcode, backups, files, AI provider accounts, and exported data."
                        )
                        
                        TermsSectionView(
                            title: "Medical Disclaimer",
                            content: "\(BisonHealthLegalCopy.noMedicalAdvice) App content, extracted data, summaries, AI outputs, and suggestions may be incomplete, inaccurate, outdated, or inappropriate for your circumstances."
                        )
                        
                        TermsSectionView(
                            title: "AI and Third-Party Services",
                            content: "If you configure external AI providers, cloud services, sharing destinations, email, messaging, storage, or other third-party services, your use of those services is governed by their terms, privacy policies, security practices, data-retention rules, and fees. BisonHealth AI does not control those third parties and is not responsible for their acts, omissions, outputs, availability, or handling of your data."
                        )

                        TermsSectionView(
                            title: "Data and Availability",
                            content: "The app is provided as a local personal tool. You are responsible for maintaining your own device, backups, exports, and copies of important information. We do not guarantee that app data, generated content, extraction results, AI outputs, imports, exports, or integrations will be error-free, complete, recoverable, or continuously available."
                        )

                        TermsSectionView(
                            title: "Prohibited Uses",
                            content: "You may not use the app for unlawful purposes, to process data you do not have rights to use, to provide medical or professional services to others, to make automated eligibility or treatment decisions, to attempt to reverse engineer restricted components, or to interfere with the app or related services."
                        )
                        
                        TermsSectionView(
                            title: "No Warranties",
                            content: "To the fullest extent permitted by law, the app is provided \"as is\" and \"as available\" without warranties of any kind, express or implied, including warranties of accuracy, reliability, merchantability, fitness for a particular purpose, non-infringement, availability, security, or error-free operation."
                        )

                        TermsSectionView(
                            title: "Limitation of Liability",
                            content: "To the fullest extent permitted by law, BisonHealth AI and its developers, owners, affiliates, and service providers will not be liable for indirect, incidental, special, consequential, exemplary, punitive, medical, health-related, data-loss, lost-profit, or business-interruption damages, or for claims arising from your use of the app, reliance on app content, third-party services, exported data, or AI outputs."
                        )

                        TermsSectionView(
                            title: "Indemnity",
                            content: "To the fullest extent permitted by law, you agree to defend, indemnify, and hold harmless BisonHealth AI and its developers, owners, affiliates, and service providers from claims, losses, liabilities, damages, costs, and expenses arising from your misuse of the app, violation of these terms, violation of law, third-party service configuration, or processing of data you did not have the right to use."
                        )
                        
                        TermsSectionView(
                            title: "Changes to Terms",
                            content: "We may update these terms from time to time. Updated terms may be posted in the app or otherwise made available. Your continued use of the app after updated terms are made available means you accept the updated terms."
                        )
                        
                        TermsSectionView(
                            title: "Contact Information",
                            content: "If you have questions about these Terms of Service, contact support@bisonnetworking.com."
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TermsSectionView: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    TermsOfServiceView()
}
