import Foundation
import MirrorCore

@MainActor final class CodexAdapter: ConversationProvider {
    let id = "codex"
    let connection: any HistoryConnection
    init(connection: any HistoryConnection = CodexConnection()) { self.connection = connection }
    private func array(_ value: JSONValue) throws -> [JSONValue] {
        guard case .array(let items) = value else { throw CodexDecoder.DecodeError.incompleteHistory }
        return items
    }

    func listConversations(query: String = "", cursor: String? = nil) async throws -> ConversationPage {
        var params: [String: JSONValue] = [
            "limit": .number(60), "sortKey": .string("updated_at"),
            "useStateDbOnly": .bool(true),
            "sourceKinds": .array([.string("cli"), .string("vscode"), .string("appServer")]),
        ]
        if !query.isEmpty { params["searchTerm"] = .string(query) }
        if let cursor { params["cursor"] = .string(cursor) }
        let response = try await connection.request("thread/list", params)
        return ConversationPage(
            conversations: try array(response["data"]).map(CodexDecoder.summary),
            nextCursor: response["nextCursor"].string)
    }

    func getConversation(id: String) async throws -> Conversation {
        try await getConversation(id: id, progress: nil)
    }
    func getConversation(id: String, progress: ConversationProgress?) async throws -> Conversation {
        try await withHistoryDeadline(ProcessInfo.processInfo.systemUptime + 45) { [self] in
            try await readConversation(id: id, progress: progress)
        }
    }
    private func readConversation(id: String, progress: ConversationProgress?) async throws -> Conversation {
        let response = try await connection.request(
            "thread/read", ["threadId": .string(id), "includeTurns": .bool(false)])
        let thread = response["thread"]
        let summary = try CodexDecoder.summary(thread)
        var messages: [Message] = []
        var itemIDs: Set<String> = []
        if thread["historyMode"].string == "paginated" {
            var cursor: String?
            var seen: Set<String> = []
            repeat {
                try Task.checkCancellation()
                var params: [String: JSONValue] = [
                    "threadId": .string(id), "limit": .number(50),
                    "sortDirection": .string("asc"), "itemsView": .string("full"),
                ]
                if let cursor { params["cursor"] = .string(cursor) }
                let page = try await connection.request("thread/turns/list", params)
                let pageTurns = try array(page["data"])
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try CodexDecoder.messages(pageTurns)
                }.value
                try Task.checkCancellation()
                messages += decoded.filter { itemIDs.insert($0.id).inserted }
                progress?(Conversation(summary: summary, messages: messages))
                cursor = page["nextCursor"].string
                if let cursor, !seen.insert(cursor).inserted {
                    throw CodexDecoder.DecodeError.incompleteHistory
                }
            } while cursor != nil
        } else {
            let full = try await connection.request(
                "thread/read", ["threadId": .string(id), "includeTurns": .bool(true)])
            let turns = try array(full["thread"]["turns"])
            messages = try await Task.detached(priority: .userInitiated) {
                try CodexDecoder.messages(turns)
            }.value
        }
        try Task.checkCancellation()
        return Conversation(summary: summary, messages: messages)
    }

    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary? {
        // Window titles are only useful if they match one unique returned title exactly.
        guard !context.windowTitle.isEmpty else { return nil }
        let page = try await listConversations(query: context.windowTitle)
        let matches = page.conversations.filter { $0.title == context.windowTitle }
        return matches.count == 1 && page.nextCursor == nil ? matches[0] : nil
    }
}
