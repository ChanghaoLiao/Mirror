import Foundation

public struct ConversationSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct Message: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let role: String
    public let text: String
    public init(id: String, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public final class Conversation: Sendable {
    public let summary: ConversationSummary
    public let messages: [Message]
    public init(summary: ConversationSummary, messages: [Message]) {
        self.summary = summary
        self.messages = messages
    }
}

public struct ReadingAnchor: Codable, Equatable, Sendable {
    public var messageID: String
    public var block: Int
    public var character: Int
    public var offset: Double
    public init(messageID: String, block: Int = 0, character: Int = 0, offset: Double = 0) {
        self.messageID = messageID
        self.block = max(0, block)
        self.character = max(0, character)
        self.offset = offset.isFinite ? offset : 0
    }
}

public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: Double = 100
    public var y: Double = 100
    public var width: Double = 490
    public var height: Double = 650
    public init() {}
}

public struct ReadingSettings: Codable, Equatable, Sendable {
    public var fontSize: Double = 15
    public init() {}
}

public struct ReferenceState: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var conversationID: String?
    public var anchor: ReadingAnchor?
    public var frame = WindowFrame()
    public var settings = ReadingSettings()
    public var collapsed = false
    public init(workspaceID: UUID, conversationID: String? = nil) {
        id = UUID()
        self.workspaceID = workspaceID
        self.conversationID = conversationID
    }
    public func duplicate() -> Self {
        var copy = self
        copy.id = UUID()
        copy.frame.x += 26
        copy.frame.y -= 26
        copy.collapsed = false
        return copy
    }
}

public struct WorkspaceState: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var providerID: String
    public var hostBundleID: String
    public var hostTitle: String
    public var conversationID: String?
    public init(providerID: String, hostBundleID: String, hostTitle: String) {
        id = UUID()
        self.providerID = providerID
        self.hostBundleID = hostBundleID
        self.hostTitle = hostTitle
    }
}

public struct SavedState: Codable, Equatable, Sendable {
    public var version = 1
    public var workspaces: [WorkspaceState] = []
    public var references: [ReferenceState] = []
    public var discoveredControls = false
    public init() {}
}
