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
                        Text("Last Updated: [Date]")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TermsSectionView(
                            title: "Acceptance of Terms",
                            content: "By using this BisonHealth AI app, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the app."
                        )
                        
                        TermsSectionView(
                            title: "Description of Service",
                            content: "BisonHealth AI is a personal health data management application that provides AI-powered assistance for understanding your health information. The app stores data locally on your device with optional encrypted cloud backup."
                        )
                        
                        TermsSectionView(
                            title: "User Responsibilities",
                            content: "You are responsible for maintaining the confidentiality of your health data and for all activities that occur under your account. You agree to provide accurate health information and to use the app for lawful purposes only."
                        )
                        
                        TermsSectionView(
                            title: "Medical Disclaimer",
                            content: "This app is not intended to diagnose, treat, cure, or prevent any disease. The information provided is for educational purposes only and should not replace professional medical advice. Always consult with qualified healthcare providers for medical decisions."
                        )
                        
                        TermsSectionView(
                            title: "Data Security",
                            content: "We implement industry-standard security measures to protect your health data. All data is encrypted at rest and in transit. However, no method of transmission over the internet is 100% secure."
                        )
                        
                        TermsSectionView(
                            title: "Limitations of Liability",
                            content: "The app is provided 'as is' without warranties of any kind. We shall not be liable for any direct, indirect, incidental, consequential, or punitive damages arising from your use of the app."
                        )
                        
                        TermsSectionView(
                            title: "Changes to Terms",
                            content: "We reserve the right to modify these terms at any time. Changes will be effective immediately upon posting within the app. Your continued use constitutes acceptance of the modified terms."
                        )
                        
                        TermsSectionView(
                            title: "Contact Information",
                            content: "If you have questions about these Terms of Service, please contact us through the app's support features."
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