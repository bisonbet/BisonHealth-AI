import SwiftUI

struct PlaceholderSection: View {
    let title: String
    let icon: String
    let description: String
    
    var body: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 4) {
                    Text("Coming Soon")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(Color(.tertiaryLabel))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } header: {
            Label(title, systemImage: icon)
        }
    }
}

#Preview {
    List {
        PlaceholderSection(
            title: "Imaging Reports",
            icon: "camera.metering.matrix",
            description: "X-rays, MRIs, CT scans, and other imaging results"
        )
        
        PlaceholderSection(
            title: "Medical Visits",
            icon: "doc.text",
            description: "Doctor's notes, specialist visits, and procedure reports"
        )
    }
}