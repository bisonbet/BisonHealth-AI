import SwiftUI

struct ChatEmptyStateView: View {
    let onStartNewChat: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                VStack(spacing: 8) {
                    Text("Bison Health AI")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Get personalized health insights based on your data")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            VStack(spacing: 16) {
                FeatureHighlight(
                    icon: "doc.text.magnifyingglass",
                    title: "Analyze Documents",
                    description: "Ask questions about your imported health documents"
                )
                
                FeatureHighlight(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track Trends",
                    description: "Understand patterns in your blood test results over time"
                )
                
                FeatureHighlight(
                    icon: "lightbulb",
                    title: "Get Insights",
                    description: "Receive personalized health recommendations and explanations"
                )
            }
            
            Button(action: onStartNewChat) {
                HStack {
                    Image(systemName: "plus.message")
                    Text("Start New Conversation")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(25)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ChatEmptyStateView {
        print("Start new chat")
    }
}