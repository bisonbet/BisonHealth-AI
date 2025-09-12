import SwiftUI

struct ConversationListView: View {
    let conversations: [ChatConversation]
    let onSelectConversation: (ChatConversation) -> Void
    let onDeleteConversation: (ChatConversation) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var conversationToDelete: ChatConversation?
    @State private var showingDeleteAlert = false
    
    var filteredConversations: [ChatConversation] {
        if searchText.isEmpty {
            return conversations
        } else {
            return conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(searchText) ||
                conversation.messages.contains { message in
                    message.content.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredConversations.isEmpty {
                    if conversations.isEmpty {
                        EmptyConversationsView()
                    } else {
                        NoSearchResultsView(searchText: searchText)
                    }
                } else {
                    ForEach(filteredConversations) { conversation in
                        ConversationRowView(
                            conversation: conversation,
                            onTap: {
                                onSelectConversation(conversation)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                conversationToDelete = conversation
                                showingDeleteAlert = true
                            }
                            .tint(.red)
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search conversations...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    conversationToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let conversation = conversationToDelete {
                        onDeleteConversation(conversation)
                    }
                    conversationToDelete = nil
                }
            } message: {
                if let conversation = conversationToDelete {
                    Text("Are you sure you want to delete \"\(conversation.title)\"? This action cannot be undone.")
                }
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: ChatConversation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(conversation.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(RelativeDateTimeFormatter().localizedString(for: conversation.updatedAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lastMessage = conversation.lastMessage {
                    HStack {
                        Image(systemName: lastMessage.role.icon)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(lastMessage.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                HStack {
                    Text("\(conversation.messageCount) messages")
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                    
                    if !conversation.includedHealthDataTypes.isEmpty {
                        Spacer()
                        
                        HStack(spacing: 4) {
                            ForEach(Array(conversation.includedHealthDataTypes).prefix(3), id: \.self) { dataType in
                                Image(systemName: dataType.icon)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                            
                            if conversation.includedHealthDataTypes.count > 3 {
                                Text("+\(conversation.includedHealthDataTypes.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EmptyConversationsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Conversations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a new conversation to begin chatting with your AI health assistant")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoSearchResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Results")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("No conversations found for \"\(searchText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConversationListView(
        conversations: [
            ChatConversation(
                title: "Blood Test Discussion",
                messages: [
                    ChatMessage(content: "Hello", role: .user),
                    ChatMessage(content: "Hi there!", role: .assistant)
                ],
                includedHealthDataTypes: [.personalInfo, .bloodTest]
            ),
            ChatConversation(
                title: "Medication Questions",
                messages: [
                    ChatMessage(content: "About my medications", role: .user)
                ],
                includedHealthDataTypes: [.personalInfo]
            )
        ],
        onSelectConversation: { _ in },
        onDeleteConversation: { _ in }
    )
}