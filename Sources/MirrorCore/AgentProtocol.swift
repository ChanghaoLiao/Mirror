import Foundation

/// The local automation interface deliberately exposes only Mirror reading controls.
public struct AgentRequest: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var action: String
    public var expectedRevision: Int?
    public var windowID: UUID?
    public var conversationID: String?
    public var messageID: String?
    public var query: String?
    public var fontSize: Double?
    public var frame: WindowFrame?
    public var newWindow: Bool?

    public init(
        action: String, requestID: UUID = UUID(), expectedRevision: Int? = nil,
        windowID: UUID? = nil, conversationID: String? = nil, messageID: String? = nil,
        query: String? = nil, fontSize: Double? = nil, frame: WindowFrame? = nil,
        newWindow: Bool? = nil
    ) {
        self.requestID = requestID
        self.action = action
        self.expectedRevision = expectedRevision
        self.windowID = windowID
        self.conversationID = conversationID
        self.messageID = messageID
        self.query = query
        self.fontSize = fontSize
        self.frame = frame
        self.newWindow = newWindow
    }

    public static let actions: Set<String> = [
        "status", "list", "open", "duplicate", "close", "hide", "show", "refresh",
        "find", "font", "frame", "bind", "unbind", "cancel", "copy",
    ]

    public var isMutation: Bool { action != "status" && action != "list" }

    public var validationError: String? {
        guard Self.actions.contains(action) else { return "Unknown Mirror action." }
        if let expectedRevision, expectedRevision < 0 { return "Revision must be nonnegative." }
        if action != "open", conversationID != nil || messageID != nil || newWindow != nil {
            return "Conversation, message and new-window options apply only to open."
        }
        if action != "find", query != nil { return "Query applies only to find." }
        if action != "font", fontSize != nil { return "Font size applies only to font." }
        if action != "frame", frame != nil { return "Window geometry applies only to frame." }
        if newWindow == true && windowID != nil {
            return "Choose an existing window or a new window, not both."
        }
        if isMutation, action != "open", windowID == nil { return "This action requires windowID." }
        if !isMutation, windowID != nil { return "Status and list do not take windowID." }
        for (label, value, maximum) in [
            ("conversationID", conversationID, 256), ("messageID", messageID, 512),
            ("query", query, 4096),
        ] {
            guard let value else { continue }
            if value.utf8.count > maximum { return "\(label) is too long." }
            if value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                return "\(label) cannot contain control characters."
            }
            if label != "query" && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(label) cannot be empty."
            }
            if label != "query" {
                let allowed = CharacterSet(
                    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./")
                if value.unicodeScalars.contains(where: { !allowed.contains($0) }) || value.contains("..") {
                    return "\(label) contains unsupported identifier characters."
                }
            }
        }
        if let conversationID, conversationID.contains("/") {
            return "conversationID cannot contain a path separator."
        }
        if let messageID {
            let parts = messageID.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count != 2 || parts.contains(where: \.isEmpty) {
                return "messageID must identify a turn and item as TURN/ITEM."
            }
        }
        if let fontSize, !fontSize.isFinite || !(11...26).contains(fontSize) {
            return "Font size must be between 11 and 26."
        }
        if let frame {
            guard [frame.x, frame.y, frame.width, frame.height].allSatisfy(\.isFinite),
                abs(frame.x) <= 100_000, abs(frame.y) <= 100_000,
                (280...100_000).contains(frame.width), (260...100_000).contains(frame.height)
            else { return "Window frame must contain finite, bounded dimensions." }
        }
        switch action {
        case "open":
            if conversationID == nil { return "Opening a reference requires conversationID." }
        case "find":
            if query == nil { return "Finding text requires query." }
        case "font":
            if fontSize == nil { return "Changing font size requires fontSize." }
        case "frame":
            if frame == nil { return "Moving a reference requires frame." }
        default: break
        }
        return nil
    }

    public func validate() throws {
        if let validationError { throw AgentProtocolError.invalidRequest(validationError) }
    }
}

public enum AgentProtocolError: Error, LocalizedError, Equatable, Sendable {
    case invalidRequest(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        }
    }
}

public struct AgentWindowSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationID: String?
    public var messageID: String?
    public var collapsed: Bool
    public var bound: Bool
    public var fontSize: Double
    public var frame: WindowFrame
    public var loading: Bool
    public var contentStatus: String?

    public init(
        id: UUID, conversationID: String? = nil, messageID: String? = nil,
        collapsed: Bool, bound: Bool, fontSize: Double, frame: WindowFrame, loading: Bool,
        contentStatus: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.messageID = messageID
        self.collapsed = collapsed
        self.bound = bound
        self.fontSize = fontSize
        self.frame = frame
        self.loading = loading
        self.contentStatus = contentStatus
    }
}

public struct AgentResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var status: String
    public var message: String?
    public var revision: Int?
    public var windows: [AgentWindowSnapshot]?
    public var windowID: UUID?
    public var binding: String?
    public var loading: Bool?
    public var agentEnabled: Bool?
    public var appVersion: String?
    public var accessibilityGranted: Bool?

    public init(
        ok: Bool, status: String, message: String? = nil, revision: Int? = nil,
        windows: [AgentWindowSnapshot]? = nil, windowID: UUID? = nil,
        binding: String? = nil, loading: Bool? = nil, agentEnabled: Bool? = nil,
        appVersion: String? = nil, accessibilityGranted: Bool? = nil
    ) {
        self.ok = ok
        self.status = status
        self.message = message
        self.revision = revision
        self.windows = windows
        self.windowID = windowID
        self.binding = binding
        self.loading = loading
        self.agentEnabled = agentEnabled
        self.appVersion = appVersion
        self.accessibilityGranted = accessibilityGranted
    }
}
