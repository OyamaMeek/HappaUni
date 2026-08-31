import Foundation
import SwiftData

@Model
final class AIConversation {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var documentName: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        documentName: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.documentID = documentID
        self.documentName = documentName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AIConversationMessage {
    @Attribute(.unique) var id: UUID
    var conversationID: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: AIMessage.Role,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.conversationID = conversationID
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
    }

    var role: AIMessage.Role {
        AIMessage.Role(rawValue: roleRawValue) ?? .assistant
    }

    func asAIMessage() -> AIMessage {
        AIMessage(id: id, role: role, content: content, createdAt: createdAt)
    }
}
