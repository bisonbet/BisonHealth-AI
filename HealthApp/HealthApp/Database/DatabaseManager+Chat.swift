import Foundation
import SQLite

// MARK: - Chat CRUD Operations
extension DatabaseManager {
    
    // MARK: - Save Conversation
    func saveConversation(_ conversation: ChatConversation) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let dataTypesJson = try JSONEncoder().encode(Array(conversation.includedHealthDataTypes))
            let dataTypesString = String(data: dataTypesJson, encoding: .utf8) ?? "[]"
            
            let tagsJson = try JSONEncoder().encode(conversation.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"
            
            let insert = chatConversationsTable.insert(or: .replace,
                conversationId <- conversation.id.uuidString,
                conversationTitle <- conversation.title,
                conversationCreatedAt <- Int64(conversation.createdAt.timeIntervalSince1970),
                conversationUpdatedAt <- Int64(conversation.updatedAt.timeIntervalSince1970),
                conversationIncludedDataTypes <- dataTypesString,
                conversationIsArchived <- conversation.isArchived,
                conversationTags <- tagsString
            )
            
            try db.run(insert)
            
            // Save all messages
            for message in conversation.messages {
                try await saveMessage(message, conversationId: conversation.id)
            }
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Conversations
    func fetchConversations() async throws -> [ChatConversation] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [ChatConversation] = []
        
        do {
            let query = chatConversationsTable
                .filter(conversationIsArchived == false)
                .order(conversationUpdatedAt.desc)
            
            for row in try db.prepare(query) {
                let conversation = try await buildChatConversation(from: row)
                results.append(conversation)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Fetch Archived Conversations
    func fetchArchivedConversations() async throws -> [ChatConversation] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [ChatConversation] = []
        
        do {
            let query = chatConversationsTable
                .filter(conversationIsArchived == true)
                .order(conversationUpdatedAt.desc)
            
            for row in try db.prepare(query) {
                let conversation = try await buildChatConversation(from: row)
                results.append(conversation)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Fetch Single Conversation
    func fetchConversation(id: UUID) async throws -> ChatConversation? {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let query = chatConversationsTable.filter(conversationId == id.uuidString)
            
            if let row = try db.pluck(query) {
                return try await buildChatConversation(from: row)
            }
            
            return nil
        } catch {
            throw DatabaseError.decryptionFailed
        }
    }
    
    // MARK: - Update Conversation
    func updateConversation(_ conversation: ChatConversation) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let dataTypesJson = try JSONEncoder().encode(Array(conversation.includedHealthDataTypes))
            let dataTypesString = String(data: dataTypesJson, encoding: .utf8) ?? "[]"
            
            let tagsJson = try JSONEncoder().encode(conversation.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"
            
            let query = chatConversationsTable.filter(conversationId == conversation.id.uuidString)
            let update = query.update(
                conversationTitle <- conversation.title,
                conversationUpdatedAt <- Int64(conversation.updatedAt.timeIntervalSince1970),
                conversationIncludedDataTypes <- dataTypesString,
                conversationIsArchived <- conversation.isArchived,
                conversationTags <- tagsString
            )
            
            let rowsUpdated = try db.run(update)
            if rowsUpdated == 0 {
                throw DatabaseError.notFound
            }
        } catch {
            if error is DatabaseError {
                throw error
            } else {
                throw DatabaseError.encryptionFailed
            }
        }
    }
    
    // MARK: - Delete Conversation
    func deleteConversation(_ conversation: ChatConversation) async throws {
        try await deleteConversation(id: conversation.id)
    }
    
    func deleteConversation(id: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        // Messages will be deleted automatically due to foreign key cascade
        let query = chatConversationsTable.filter(conversationId == id.uuidString)
        let rowsDeleted = try db.run(query.delete())
        
        if rowsDeleted == 0 {
            throw DatabaseError.notFound
        }
    }
    
    // MARK: - Save Message
    func addMessage(to conversationId: UUID, message: ChatMessage) async throws {
        try await saveMessage(message, conversationId: conversationId)
        
        // Update conversation's updatedAt timestamp
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = chatConversationsTable.filter(self.conversationId == conversationId.uuidString)
        let update = query.update(conversationUpdatedAt <- Int64(Date().timeIntervalSince1970))
        try db.run(update)
    }
    
    private func saveMessage(_ message: ChatMessage, conversationId: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let encryptedContent = try encryptString(message.content)
            let metadataJson = try message.metadata.map { try JSONSerialization.data(withJSONObject: $0) }
            let metadataString = metadataJson.map { String(data: $0, encoding: .utf8) } ?? nil
            
            let insert = chatMessagesTable.insert(or: .replace,
                messageId <- message.id.uuidString,
                messageConversationId <- conversationId.uuidString,
                messageContent <- encryptedContent,
                messageRole <- message.role.rawValue,
                messageTimestamp <- Int64(message.timestamp.timeIntervalSince1970),
                messageMetadata <- metadataString,
                messageIsError <- message.isError,
                messageTokens <- message.tokens,
                messageProcessingTime <- message.processingTime
            )
            
            try db.run(insert)
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Messages for Conversation
    func fetchMessages(for conversationId: UUID) async throws -> [ChatMessage] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [ChatMessage] = []
        
        do {
            let query = chatMessagesTable
                .filter(messageConversationId == conversationId.uuidString)
                .order(messageTimestamp.asc)
            
            for row in try db.prepare(query) {
                let message = try buildChatMessage(from: row)
                results.append(message)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Search Conversations
    func searchConversations(query: String) async throws -> [ChatConversation] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [ChatConversation] = []
        let searchTerm = "%\(query.lowercased())%"
        
        do {
            let sqlQuery = chatConversationsTable
                .filter(conversationTitle.like(searchTerm))
                .order(conversationUpdatedAt.desc)
            
            for row in try db.prepare(sqlQuery) {
                let conversation = try await buildChatConversation(from: row)
                results.append(conversation)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Chat Statistics
    func getChatStatistics() async throws -> ChatStatistics {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let totalConversations = try db.scalar(chatConversationsTable.count)
        let totalMessages = try db.scalar(chatMessagesTable.count)
        
        // Get total tokens used
        let totalTokens: Int = try db.scalar(chatMessagesTable.select(messageTokens.sum)) ?? 0
        
        // Get average response time
        let avgResponseTime: Double = try db.scalar(chatMessagesTable
            .filter(messageRole == MessageRole.assistant.rawValue && messageProcessingTime != nil)
            .select(messageProcessingTime.average)) ?? 0.0
        
        // Get last chat date
        let lastChatTimestamp: Int64? = try db.scalar(chatConversationsTable.select(conversationUpdatedAt.max))
        let lastChatDate = lastChatTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        
        return ChatStatistics(
            totalConversations: totalConversations,
            totalMessages: totalMessages,
            totalTokensUsed: totalTokens,
            averageResponseTime: avgResponseTime,
            mostUsedDataTypes: [], // TODO: Implement this calculation
            lastChatDate: lastChatDate
        )
    }
    
    // MARK: - Helper Methods
    private func buildChatConversation(from row: Row) async throws -> ChatConversation {
        let id = UUID(uuidString: row[conversationId]) ?? UUID()
        let title = row[conversationTitle]
        let createdAt = Date(timeIntervalSince1970: TimeInterval(row[conversationCreatedAt]))
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(row[conversationUpdatedAt]))
        let isArchived = row[conversationIsArchived]
        
        // Decode included data types
        let dataTypesString = row[conversationIncludedDataTypes]
        let dataTypesData = dataTypesString.data(using: .utf8) ?? Data()
        let dataTypesArray = (try? JSONDecoder().decode([HealthDataType].self, from: dataTypesData)) ?? []
        let includedDataTypes = Set(dataTypesArray)
        
        // Decode tags
        let tagsString = row[conversationTags]
        let tagsData = tagsString.data(using: .utf8) ?? Data()
        let tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
        
        // Fetch messages
        let messages = try await fetchMessages(for: id)
        
        return ChatConversation(
            id: id,
            title: title,
            messages: messages,
            createdAt: createdAt,
            updatedAt: updatedAt,
            includedHealthDataTypes: includedDataTypes,
            isArchived: isArchived,
            tags: tags
        )
    }
    
    private func buildChatMessage(from row: Row) throws -> ChatMessage {
        let id = UUID(uuidString: row[messageId]) ?? UUID()
        let encryptedContent = row[messageContent]
        let content = try decryptString(encryptedContent)
        let role = MessageRole(rawValue: row[messageRole]) ?? .user
        let timestamp = Date(timeIntervalSince1970: TimeInterval(row[messageTimestamp]))
        let isError = row[messageIsError]
        let tokens = row[messageTokens]
        let processingTime = row[messageProcessingTime]
        
        // Decode metadata
        var metadata: [String: String]? = nil
        if let metadataString = row[messageMetadata],
           let metadataData = metadataString.data(using: .utf8),
           let metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: String] {
            metadata = metadataDict
        }
        
        return ChatMessage(
            id: id,
            content: content,
            role: role,
            timestamp: timestamp,
            metadata: metadata,
            isError: isError,
            tokens: tokens,
            processingTime: processingTime
        )
    }
}