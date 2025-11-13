import SwiftUI
import MarkdownUI
import UIKit

struct ChatDetailView: View {
    @ObservedObject var chatManager: AIChatManager
    @State private var messageText: String = ""
    @Binding var showingContextSelector: Bool
    let isIPad: Bool
    
    @State private var showingConversationSettings = false
    @State private var showingExportOptions = false
    @State private var showingClearConfirmation = false
    @State private var showingDoctorSelector = false
    @State private var showingAIDocumentSelector = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @FocusState private var isMessageInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if let conversation = chatManager.currentConversation {
                conversationContentView(conversation: conversation)
            } else {
                emptyStateView
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside the input field
            isMessageInputFocused = false
        }
        .navigationTitle(chatManager.currentConversation?.title ?? "BisonHealth AI")
        .navigationBarTitleDisplayMode(isIPad ? .inline : .large)
        .toolbar {
            if chatManager.currentConversation != nil {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        menuContent
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
        .sheet(isPresented: $showingDoctorSelector) {
            DoctorSelectorView(
                selectedDoctor: $chatManager.selectedDoctor,
                onSave: { doctor in
                    chatManager.selectDoctor(doctor)
                }
            )
        }
        .sheet(isPresented: $showingAIDocumentSelector) {
            UnifiedContextSelectorView(chatManager: chatManager)
                .presentationDetents([.large])
        }
        .confirmationDialog("Clear Messages", isPresented: $showingClearConfirmation) {
            Button("Clear All Messages", role: .destructive) {
                clearConversation()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all messages in this conversation. This action cannot be undone.")
        }
        .onAppear {
            if isIPad {
                // Auto-focus message input on iPad
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isMessageInputFocused = true
                }
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
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
        
        // Keyboard accessory to dismiss keyboard
        if isMessageInputFocused {
            keyboardAccessoryView
        }
        
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
    
    private var keyboardAccessoryView: some View {
        HStack {
            Button(action: {
                showingContextSelector = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.text.square")
                    Text("Health Data")
                }
            }
            .font(.caption)
            .foregroundColor(.blue)

            Button(action: {
                showingDoctorSelector = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "stethoscope")
                    Text("Doctor")
                }
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.leading, 8)
            
            Spacer()
            
            Button(action: {
                isMessageInputFocused = false
            }) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                    } else {
                        // On iPhone, dismiss keyboard after sending to show tab bar
                        isMessageInputFocused = false
                    }
                }
            } catch {
                // Show user-facing error alert
                errorMessage = "Failed to send message: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
    
    private func clearConversation() {
        guard let conversation = chatManager.currentConversation else { return }
        
        Task {
            do {
                try await chatManager.clearConversationMessages(conversation)
            } catch {
                errorMessage = "Failed to clear conversation: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
    
    @ViewBuilder
    private var menuContent: some View {
        Button("Conversation Settings", systemImage: "gear") {
            showingConversationSettings = true
        }

        Button("Health Data", systemImage: "heart.text.square") {
            showingAIDocumentSelector = true
        }

        Divider()

        Button("Export Conversation", systemImage: "square.and.arrow.up") {
            showingExportOptions = true
        }

        Button("Clear Messages", systemImage: "trash", role: .destructive) {
            showingClearConfirmation = true
        }
    }
}

struct ContextIndicatorView: View {
    let includedTypes: Set<HealthDataType>
    let onEditContext: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square")
                    .font(.caption)
                    .foregroundColor(.blue)

                Text("Sharing:")
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
                    ForEach(messages.filter { !$0.content.isEmpty }) { message in
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
                    
                    // Use MarkdownUI for assistant messages (which contain markdown from AI doctor)
                    // Keep plain Text for user messages
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
                        } else {
                            // On iPhone, dismiss keyboard after sending to show tab bar
                            isTextFieldFocused = false
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
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var useStreaming = true
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
                    
                    HStack {
                        Text("Model")
                        Spacer()
                        Text(settingsManager.modelPreferences.chatModel)
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Change Model") {
                        Text("To change the AI model, go to Settings > Models")
                            .navigationTitle("Model Selection")
                            .navigationBarTitleDisplayMode(.inline)
                    }
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
    @StateObject private var exporter = ConversationExporter(fileSystemManager: FileSystemManager.shared)

    @State private var selectedFormat: ExportFormat = .pdf
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false

    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case markdown = "Markdown"

        var displayName: String { rawValue }
        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            case .markdown: return "doc.text.fill"
            }
        }
        var description: String {
            switch self {
            case .pdf: return "Well-formatted PDF document"
            case .markdown: return "Plain text markdown format"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let conv = conversation {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conv.title)
                                .font(.headline)
                            HStack {
                                Text("\(conv.messages.count) messages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDate(conv.updatedAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Conversation")
                }

                Section {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        HStack {
                            Image(systemName: format.icon)
                                .foregroundColor(.blue)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(format.displayName)
                                    .font(.body)
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFormat = format
                        }
                    }
                } header: {
                    Text("Export Format")
                }

                Section {
                    Button(action: exportConversation) {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isExporting ? "Exporting..." : "Export Conversation")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isExporting || conversation == nil)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Export Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private func exportConversation() {
        guard let conversation = conversation else {
            errorMessage = "No conversation to export"
            showingError = true
            return
        }

        isExporting = true
        errorMessage = nil

        Task {
            do {
                let exportURL: URL

                switch selectedFormat {
                case .pdf:
                    exportURL = try await exporter.exportConversationAsPDF(conversation)
                case .markdown:
                    exportURL = try await exporter.exportConversationAsMarkdown(conversation)
                }

                await MainActor.run {
                    exportedFileURL = exportURL
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isExporting = false
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    ChatDetailView(
        chatManager: AIChatManager(
            healthDataManager: HealthDataManager.shared,
            databaseManager: DatabaseManager.shared
        ),
        showingContextSelector: .constant(false),
        isIPad: true
    )
}