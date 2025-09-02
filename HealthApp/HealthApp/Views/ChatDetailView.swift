import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var chatManager: AIChatManager
    @Binding var messageText: String
    @Binding var showingContextSelector: Bool
    let isIPad: Bool
    
    @State private var showingConversationSettings = false
    @State private var showingExportOptions = false
    @FocusState private var isMessageInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if let conversation = chatManager.currentConversation {
                conversationContentView(conversation: conversation)
            } else {
                emptyStateView
            }
        }
        .navigationTitle(chatManager.currentConversation?.title ?? "BisonHealth AI")
        .navigationBarTitleDisplayMode(isIPad ? .inline : .large)
        .toolbar {
            if chatManager.currentConversation != nil {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !isIPad {
                        Button("Context") {
                            showingContextSelector = true
                        }
                        .font(.caption)
                    }
                    
                    Menu {
                        Button("Edit Context", systemImage: "slider.horizontal.3") {
                            showingContextSelector = true
                        }
                        
                        Button("Conversation Settings", systemImage: "gear") {
                            showingConversationSettings = true
                        }
                        
                        Divider()
                        
                        Button("Export Conversation", systemImage: "square.and.arrow.up") {
                            showingExportOptions = true
                        }
                        
                        Button("Clear Messages", systemImage: "trash", role: .destructive) {
                            clearConversation()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingConversationSettings) {
            ConversationSettingsView(
                conversation: chatManager.currentConversation,
                onSave: { updatedConversation in
                    // Handle conversation updates
                }
            )
        }
        .sheet(isPresented: $showingExportOptions) {
            ConversationExportView(
                conversation: chatManager.currentConversation
            )
        }
        .onAppear {
            if isIPad {
                // Auto-focus message input on iPad
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isMessageInputFocused = true
                }
            }
        }
        // Note: iPad keyboard shortcuts would be implemented using
        // toolbar buttons with .keyboardShortcut modifiers
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func conversationContentView(conversation: ChatConversation) -> some View {
        // Connection status indicator
        if !chatManager.isConnected {
            ConnectionStatusBanner(
                isOffline: chatManager.isOffline,
                onRetry: {
                    Task {
                        await chatManager.checkConnection()
                    }
                }
            )
        }
        
        // Context indicator for iPad
        if isIPad && !conversation.includedHealthDataTypes.isEmpty {
            ContextIndicatorView(
                includedTypes: conversation.includedHealthDataTypes,
                onEditContext: {
                    showingContextSelector = true
                }
            )
        }
        
        // Messages list with iPad optimizations
        EnhancedMessageListView(
            messages: conversation.messages,
            isLoading: chatManager.isLoading,
            isIPad: isIPad
        )
        
        // Message input with keyboard shortcuts
        messageInputView
    }
    
    private var emptyStateView: some View {
        ChatEmptyStateView(
            onStartNewChat: {
                Task {
                    _ = try await chatManager.startNewConversation()
                }
            }
        )
    }
    
    private var messageInputView: some View {
        EnhancedMessageInputView(
            text: $messageText,
            isEnabled: chatManager.isConnected && !chatManager.isOffline,
            isIPad: isIPad,
            onSend: {
                sendMessage()
            },
            onContextTap: {
                showingContextSelector = true
            }
        )
        .focused($isMessageInputFocused)
    }
    
    private func sendMessage() {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        Task {
            do {
                // Use streaming by default for better user experience
                try await chatManager.sendMessage(message, useStreaming: true)
                await MainActor.run {
                    messageText = ""
                    if isIPad {
                        isMessageInputFocused = true
                    }
                }
            } catch {
                // Error handling is managed by the chat manager
                print("Failed to send message: \(error)")
            }
        }
    }
    
    private func clearConversation() {
        // Implementation for clearing conversation messages
        Task {
            // This would need to be implemented in the chat manager
            print("Clear conversation not yet implemented")
        }
    }
}

struct ContextIndicatorView: View {
    let includedTypes: Set<HealthDataType>
    let onEditContext: () -> Void
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("Context:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(Array(includedTypes).prefix(4), id: \.self) { dataType in
                        Text(dataType.shortName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if includedTypes.count > 4 {
                        Text("+\(includedTypes.count - 4)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Button("Edit") {
                onEditContext()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

struct EnhancedMessageListView: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let isIPad: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: isIPad ? 16 : 12) {
                    ForEach(messages) { message in
                        EnhancedMessageBubbleView(
                            message: message,
                            isIPad: isIPad
                        )
                        .id(message.id)
                    }
                    
                    if isLoading {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, isIPad ? 24 : 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) {
                if isLoading {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct EnhancedMessageBubbleView: View {
    let message: ChatMessage
    let isIPad: Bool
    
    @State private var showingCopyConfirmation = false
    
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
                        .textSelection(.enabled) // Enable text selection on iPad
                    
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
                    
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(message.isError ? Color.red.opacity(0.1) : Color(.systemGray6))
                        .foregroundColor(message.isError ? .red : .primary)
                        .cornerRadius(18)
                        .textSelection(.enabled) // Enable text selection on iPad
                    
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
            
            if !message.isFromUser {
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

struct EnhancedMessageInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let isIPad: Bool
    let onSend: () -> Void
    let onContextTap: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                // Context button for iPad
                if isIPad {
                    Button(action: onContextTap) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                }
                
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
                            // On iPad, Enter sends message, Shift+Enter adds new line
                            onSend()
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

// Placeholder views for sheets
struct ConversationSettingsView: View {
    let conversation: ChatConversation?
    let onSave: (ChatConversation) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var useStreaming = true
    @State private var selectedModel = "llama3.2"
    @State private var conversationTitle = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Conversation") {
                    TextField("Title", text: $conversationTitle)
                        .onAppear {
                            conversationTitle = conversation?.title ?? ""
                        }
                }
                
                Section("AI Settings") {
                    Toggle("Streaming Responses", isOn: $useStreaming)
                    
                    Picker("Model", selection: $selectedModel) {
                        Text("Llama 3.2").tag("llama3.2")
                        Text("Llama 3.1").tag("llama3.1")
                        Text("Llama 2").tag("llama2")
                        Text("Code Llama").tag("codellama")
                    }
                    .pickerStyle(.menu)
                }
                
                Section {
                    Text("Streaming responses provide real-time feedback as the AI generates text, creating a more interactive experience.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Save settings logic would go here
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ConversationExportView: View {
    let conversation: ChatConversation?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Export Options") {
                    Text("Export functionality coming soon...")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Export")
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

#Preview {
    ChatDetailView(
        chatManager: AIChatManager(
            ollamaClient: OllamaClient.shared,
            healthDataManager: HealthDataManager.shared,
            databaseManager: DatabaseManager.shared
        ),
        messageText: .constant(""),
        showingContextSelector: .constant(false),
        isIPad: true
    )
}