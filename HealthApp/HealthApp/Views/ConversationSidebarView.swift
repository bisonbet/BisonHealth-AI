import SwiftUI

struct ConversationSidebarView: View {
    let conversations: [ChatConversation]
    @Binding var selectedConversationId: UUID?
    @Binding var searchText: String
    let onSelectConversation: (ChatConversation) -> Void
    let onNewConversation: () -> Void
    let onDeleteConversation: (ChatConversation) -> Void
    
    @State private var showingSearchResults = false
    @State private var filteredConversations: [ChatConversation] = []
    
    var displayedConversations: [ChatConversation] {
        if searchText.isEmpty {
            return conversations.filter { !$0.isArchived }
        } else {
            return filteredConversations
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            VStack(spacing: 12) {
                HStack {
                    Text("Conversations")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: onNewConversation) {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                }
                
                // Search bar optimized for iPad
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                    
                    if !searchText.isEmpty {
                        Button("Clear") {
                            searchText = ""
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Divider()
            
            // Conversations list
            if displayedConversations.isEmpty {
                SidebarEmptyConversationsView(
                    isSearching: !searchText.isEmpty,
                    searchText: searchText,
                    onNewConversation: onNewConversation
                )
            } else {
                List(displayedConversations, selection: $selectedConversationId) { conversation in
                    ConversationSidebarRowView(
                        conversation: conversation,
                        isSelected: selectedConversationId == conversation.id,
                        onTap: {
                            onSelectConversation(conversation)
                        },
                        onDelete: {
                            onDeleteConversation(conversation)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: searchText) { _, newValue in
            performSearch(newValue)
        }
    }
    
    private func performSearch(_ query: String) {
        if query.isEmpty {
            filteredConversations = []
            showingSearchResults = false
        } else {
            filteredConversations = conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(query) ||
                conversation.messages.contains { message in
                    message.content.localizedCaseInsensitiveContains(query)
                }
            }
            showingSearchResults = true
        }
    }
}

struct ConversationSidebarRowView: View {
    let conversation: ChatConversation
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(conversation.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Text(RelativeDateTimeFormatter().localizedString(for: conversation.updatedAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lastMessage = conversation.lastMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: lastMessage.role.icon)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                        
                        Text(lastMessage.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
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
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
        )
        .contextMenu {
            Button("Delete Conversation", systemImage: "trash", role: .destructive) {
                showingDeleteAlert = true
            }
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
    }
}

struct SidebarEmptyConversationsView: View {
    let isSearching: Bool
    let searchText: String
    let onNewConversation: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isSearching ? "magnifyingglass" : "message.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(isSearching ? "No Results" : "No Conversations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(isSearching ? 
                     "No conversations found for \"\(searchText)\"" :
                     "Start a new conversation to begin chatting with your AI health assistant"
                )
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            
            if !isSearching {
                Button("Start New Conversation") {
                    onNewConversation()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConversationSidebarView(
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
        selectedConversationId: .constant(nil),
        searchText: .constant(""),
        onSelectConversation: { _ in },
        onNewConversation: { },
        onDeleteConversation: { _ in }
    )
}