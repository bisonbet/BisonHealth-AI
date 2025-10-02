import SwiftUI

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
                            color: .blue,
                            content: "BisonHealth AI is designed exclusively for individual, personal health tracking and management."
                        )
                        
                        disclaimerCard(
                            title: "Not HIPAA Compliant",
                            icon: "building.2.fill",
                            color: .red,
                            content: "This application is NOT intended for use by healthcare providers, clinics, or any professional or enterprise environments. We do not provide Business Associate Agreements (BAAs) or HIPAA-compliant guarantees."
                        )
                        
                        disclaimerCard(
                            title: "Your Responsibility",
                            icon: "hand.raised.fill",
                            color: .orange,
                            content: "You are responsible for ensuring your use complies with all applicable laws and regulations. Do not use this app for managing patient data or professional healthcare activities."
                        )
                    }
                    
                    // Detailed information section
                    VStack(spacing: 16) {
                        Button(action: { showingDetailedInfo = true }) {
                            HStack {
                                Text("Learn More About Our Privacy & Security")
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(.blue)
                        }
                        
                        Text("By using this app, you acknowledge that you have read, understood, and agree to these terms.")
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
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Text("You must accept these terms to use BisonHealth AI")
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
                    // Privacy & Security Overview
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Privacy & Security")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            privacyItem(
                                icon: "lock.fill",
                                title: "Local Storage",
                                description: "All health data is encrypted and stored locally on your device"
                            )
                            
                            privacyItem(
                                icon: "eye.slash.fill",
                                title: "No Tracking",
                                description: "No analytics, tracking, or data collection"
                            )
                            
                            privacyItem(
                                icon: "person.crop.circle",
                                title: "Individual Control",
                                description: "You maintain complete control over your personal data"
                            )
                            
                            privacyItem(
                                icon: "exclamationmark.triangle.fill",
                                title: "Consumer-Grade Protection",
                                description: "Privacy safeguards appropriate for personal use, not HIPAA compliance"
                            )
                        }
                    }
                    
                    Divider()
                    
                    // What This Means
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What This Means")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("✅ Perfect For:")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• Managing your own personal health data")
                                Text("• Getting AI-powered insights about your health")
                                Text("• Organizing your health documents")
                                Text("• Tracking your personal health journey")
                            }
                            .padding(.leading, 16)
                            
                            Text("❌ Not Suitable For:")
                                .font(.headline)
                                .foregroundColor(.red)
                                .padding(.top, 16)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• Healthcare providers managing patient data")
                                Text("• Professional or clinical environments")
                                Text("• Enterprise or organizational use")
                                Text("• Any HIPAA-regulated activities")
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
                        
                        Text("As a user, you are responsible for ensuring that your use of BisonHealth AI complies with all applicable laws and regulations. If you are a healthcare provider or work in a regulated environment, you must not use this application for managing patient data or any professional healthcare activities.")
                            .font(.body)
                    }
                    
                    Divider()
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Questions?")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("If you have questions about appropriate use or need HIPAA-compliant solutions, please seek appropriate professional tools that provide Business Associate Agreements and HIPAA compliance guarantees.")
                            .font(.body)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Privacy & Security Details")
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
                .foregroundColor(.blue)
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
        print("Disclaimer accepted")
    }
}
