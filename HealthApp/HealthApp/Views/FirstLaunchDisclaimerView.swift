import SwiftUI

enum BisonHealthLegalCopy {
    static let personalUseSummaryShort = "BisonHealth AI is for organizing your own health information."
    static let personalUseSummary = "BisonHealth AI is for organizing your own health information. You can use it to store records, summarize documents, and prepare questions for your clinician."
    static let notForProfessionalUse = "Do not use it for patient care, clinic operations, professional healthcare workflows, employer or insurance decisions, or any HIPAA-regulated work."
    static let noHIPAAGuarantee = "We do not provide Business Associate Agreements (BAAs), HIPAA compliance guarantees, or HIPAA-regulated data-processing services."
    static let noMedicalAdvice = "The app is not a medical device and does not provide medical advice, diagnosis, treatment, triage, monitoring, prescribing, or emergency help. Talk to a qualified healthcare professional before making medical decisions. For emergencies, call emergency services."
    static let userResponsibility = "You are responsible for the information you enter, import, generate, export, share, or send to third-party services, and for using the app only where you have the right to manage that information."
}

struct FirstLaunchDisclaimerView: View {
    @State private var showingDetailedInfo = false
    @StateObject private var appSettingsManager = AppSettingsManager.shared
    let onAccept: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Important Notice")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Main disclaimer content
                    VStack(spacing: 20) {
                        disclaimerCard(
                            title: "Personal Use Only",
                            icon: "person.fill",
                            color: BisonTheme.gold,
                            content: BisonHealthLegalCopy.personalUseSummary
                        )
                        
                        disclaimerCard(
                            title: "Not for Professional or HIPAA-Regulated Use",
                            icon: "building.2.fill",
                            color: .red,
                            content: "\(BisonHealthLegalCopy.notForProfessionalUse) \(BisonHealthLegalCopy.noHIPAAGuarantee)"
                        )
                        
                        disclaimerCard(
                            title: "Not Medical Advice",
                            icon: "hand.raised.fill",
                            color: .orange,
                            content: BisonHealthLegalCopy.noMedicalAdvice
                        )
                    }
                    
                    // Detailed information section
                    VStack(spacing: 16) {
                        Button(action: { showingDetailedInfo = true }) {
                            HStack {
                                Text("Read the Full Disclaimer")
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(BisonTheme.gold)
                        }
                        
                        Text("By using this app, you acknowledge that you have read, understood, and agree to this notice, the Privacy Policy, and the Terms of Service.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDetailedInfo) {
                DetailedDisclaimerView()
            }
            .safeAreaInset(edge: .bottom) {
                // Accept button
                VStack(spacing: 16) {
                    Button(action: {
                        onAccept()
                    }) {
                        Text("I Understand and Accept")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BisonTheme.gold)
                            .cornerRadius(12)
                    }
                    
                    Text("You must accept this notice to use BisonHealth AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .background(Color(UIColor.systemBackground))
            }
        }
    }
    
    private func disclaimerCard(title: String, icon: String, color: Color, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct DetailedDisclaimerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Privacy & Data Overview
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Privacy & Data")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            privacyItem(
                                icon: "lock.fill",
                                title: "Local Storage",
                                description: "Your app data is stored on your device. Health data, documents, chats, and appointment prep records are encrypted by the app."
                            )
                            
                            privacyItem(
                                icon: "eye.slash.fill",
                                title: "No Tracking",
                                description: "BisonHealth AI does not collect analytics, tracking data, crash reports, or advertising identifiers."
                            )
                            
                            privacyItem(
                                icon: "person.crop.circle",
                                title: "Individual Control",
                                description: "You control what you enter, import, export, share, or send to external AI providers."
                            )
                            
                            privacyItem(
                                icon: "exclamationmark.triangle.fill",
                                title: "Not HIPAA Compliant",
                                description: BisonHealthLegalCopy.noHIPAAGuarantee
                            )
                        }
                    }
                    
                    Divider()
                    
                    // What This Means
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Appropriate Use")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Use It For")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• Organizing your own health records")
                                Text("• Summarizing your own documents")
                                Text("• Preparing questions for your clinician")
                                Text("• Tracking information for personal reference")
                            }
                            .padding(.leading, 16)
                            
                            Text("Do Not Use It For")
                                .font(.headline)
                                .foregroundColor(.red)
                                .padding(.top, 16)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• Patient care or clinic operations")
                                Text("• Professional healthcare workflows")
                                Text("• Employer or insurance decisions")
                                Text("• Any HIPAA-regulated work")
                            }
                            .padding(.leading, 16)
                        }
                    }
                    
                    Divider()
                    
                    // Your Responsibility
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Responsibility")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(BisonHealthLegalCopy.userResponsibility)
                            .font(.body)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Medical Disclaimer")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(BisonHealthLegalCopy.noMedicalAdvice)
                            .font(.body)
                    }
                    
                    Divider()
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Questions?")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("If you need HIPAA-compliant tools or professional healthcare software, use a product that provides the appropriate Business Associate Agreement and compliance commitments.")
                            .font(.body)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Full Disclaimer")
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
    
    private func privacyItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(BisonTheme.gold)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    FirstLaunchDisclaimerView {
        AppLog.shared.ui("Disclaimer accepted")
    }
}
