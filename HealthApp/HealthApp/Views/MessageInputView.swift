import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Type your message...", text: $text, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .focused($isTextFieldFocused)
                    .disabled(!isEnabled)
                    .lineLimit(1...8)
                    .onSubmit {
                        if isIPad {
                            // On iPad, Enter sends message
                            if canSend {
                                onSend()
                            }
                        }
                    }
                
                Button(action: {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                        if isIPad {
                            // Keep focus on iPad for continuous typing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .blue : .secondary)
                }
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: isIPad ? [.command] : [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
    
    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    VStack {
        Spacer()
        
        MessageInputView(
            text: .constant(""),
            isEnabled: true,
            onSend: {}
        )
    }
}