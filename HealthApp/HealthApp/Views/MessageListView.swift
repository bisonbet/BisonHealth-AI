import SwiftUI
import MarkdownUI

struct MessageListView: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                    
                    if isLoading {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            // Watch for content changes in streaming messages
            .onChange(of: messages.map { $0.content }) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage
    
    @State private var showingCopyConfirmation = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var markdownContentView: some View {
        buildMarkdownView()
    }
    
    private func buildMarkdownView() -> some View {
        applyTextStyles(
            applyBlockStyles(
                applyCodeStyles(
                    applyLinkAndListStyles(
                        Markdown(message.content).markdownTheme(.gitHub)
                    )
                )
            )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(18)
        .textSelection(.enabled)
    }
    
    private func applyTextStyles<Content: View>(_ content: Content) -> some View {
        content.markdownTextStyle(\.text) {
            FontSize(.em(1))
            ForegroundColor(.primary)
        }
    }
    
    private func applyBlockStyles<Content: View>(_ content: Content) -> some View {
        content
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .markdownMargin(top: .em(0), bottom: .em(0.5))
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.25))
                        FontWeight(.bold)
                    }
                    .markdownMargin(top: .em(0.5), bottom: .em(0.25))
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(.em(1.15))
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: .em(0.5), bottom: .em(0.25))
            }
    }
    
    private func applyCodeStyles<Content: View>(_ content: Content) -> some View {
        content
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                    }
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                    .markdownMargin(top: .em(0.5), bottom: .em(0.5))
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                ForegroundColor(.blue)
                BackgroundColor(Color(.systemGray5))
            }
    }
    
    private func applyLinkAndListStyles<Content: View>(_ content: Content) -> some View {
        content
            .markdownTextStyle(\.link) {
                ForegroundColor(.blue)
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.25))
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 4)
                    }
                    .markdownMargin(top: .em(0.5), bottom: .em(0.5))
            }
    }
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer(minLength: isIPad ? 100 : 50)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .textSelection(.enabled)
                    
                    Text(message.formattedTimestamp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "brain.head.profile")
                            .foregroundColor(message.isError ? .red : .green)
                            .font(.caption)
                        
                        Text(message.role.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        // Use MarkdownUI for assistant messages (which contain markdown from AI doctor)
                        // Keep plain Text for user messages and errors
                        if message.isError {
                            Text(message.content)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(18)
                                .textSelection(.enabled)
                        } else {
                            markdownContentView
                        }
                        
                        // Show streaming indicator for messages being typed
                        if message.role == .assistant && message.content.isEmpty {
                            StreamingIndicatorView()
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(message.formattedTimestamp)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let tokens = message.tokens {
                            Text("• \(tokens) tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let processingTime = message.processingTime {
                            Text("• \(String(format: "%.1f", processingTime))s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer(minLength: isIPad ? 100 : 50)
            }
        }
        .contextMenu {
            Button("Copy Message", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = message.content
                showingCopyConfirmation = true
            }
            
            if !message.isFromUser && isIPad {
                Button("Copy Response", systemImage: "doc.on.doc.fill") {
                    UIPasteboard.general.string = message.content
                    showingCopyConfirmation = true
                }
            }
        }
        .alert("Copied", isPresented: $showingCopyConfirmation) {
            Button("OK") { }
        } message: {
            Text("Message copied to clipboard")
        }
    }
}

struct TypingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.green)
                        .font(.caption)

                    Text("BisonHealth AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isAnimating ? 1.2 : 0.8)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(18)
            }

            Spacer(minLength: 50)
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

struct StreamingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 8)
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

#Preview {
    MessageListView(
        messages: [
            ChatMessage(
                content: "Hello, I'd like to discuss my recent blood test results.",
                role: .user
            ),
            ChatMessage(
                content: "I'd be happy to help you understand your blood test results. Could you please share which specific values you'd like to discuss?",
                role: .assistant,
                tokens: 25,
                processingTime: 1.2
            ),
            ChatMessage(
                content: "My cholesterol levels seem high. The total cholesterol is 240 mg/dL.",
                role: .user
            )
        ],
        isLoading: true
    )
}