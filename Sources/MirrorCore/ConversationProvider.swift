import Foundation

public struct ConversationPage: Sendable {
    public let conversations: [ConversationSummary]
    public let nextCursor: String?
    public init(conversations: [ConversationSummary], nextCursor: String?) {
        self.conversations = conversations
        self.nextCursor = nextCursor
    }
}

public struct HostContext: Sendable {
    public let bundleID: String
    public let windowTitle: String
    public let selectedText: String?
    public init(bundleID: String, windowTitle: String, selectedText: String? = nil) {
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.selectedText = selectedText
    }
}

public typealias ConversationProgress = @MainActor @Sendable (Conversation) -> Void

@MainActor public protocol ConversationProvider: AnyObject {
    var id: String { get }
    func listConversations(query: String, cursor: String?) async throws -> ConversationPage
    func getConversation(id: String) async throws -> Conversation
    func getConversation(id: String, progress: ConversationProgress?) async throws -> Conversation
    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary?
}

@MainActor extension ConversationProvider {
    public func getConversation(id: String, progress: ConversationProgress?) async throws -> Conversation {
        try await getConversation(id: id)
    }
    public func getMessages(conversationID: String) async throws -> [Message] {
        try await getConversation(id: conversationID).messages
    }
    public func searchConversations(_ query: String, cursor: String? = nil) async throws -> ConversationPage {
        try await listConversations(query: query, cursor: cursor)
    }
}

@MainActor public final class ConversationStore {
    private struct Cached {
        let conversation: Conversation
        let bytes: Int
        var access: UInt64
    }
    private struct Pending {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Conversation, Error>]
        var progress: [UUID: ConversationProgress]
        var partial: Conversation?
    }
    private let provider: ConversationProvider
    private var cache: [String: Cached] = [:]
    private var loading: [String: Pending] = [:]
    private var owners: [UUID: String] = [:]
    private var observers: [UUID: ConversationProgress] = [:]
    public func observe(owner: UUID, update: @escaping ConversationProgress) { observers[owner] = update }
    private var clock: UInt64 = 0
    private let byteLimit: Int
    private let entryLimit: Int
    public var cachedCount: Int { cache.count }
    public var pendingCount: Int { loading.count }
    public init(provider: ConversationProvider, byteLimit: Int = 32 * 1024 * 1024, entryLimit: Int = 8) {
        self.provider = provider
        self.byteLimit = byteLimit
        self.entryLimit = entryLimit
    }
    public func hold(_ id: String, owner: UUID) {
        owners[owner] = id
        trim()
    }
    public func release(owner: UUID, removeObserver: Bool = true) {
        owners[owner] = nil
        if removeObserver { observers[owner] = nil }
        trim()
    }

    public func conversation(_ id: String, refresh: Bool = false, progress: ConversationProgress? = nil)
        async throws -> Conversation
    {
        try Task.checkCancellation()
        clock &+= 1
        if !refresh, var cached = cache[id] {
            cached.access = clock
            cache[id] = cached
            return cached.conversation
        }
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if var pending = loading[id] {
                    pending.waiters[waiter] = continuation
                    pending.progress[waiter] = progress
                    loading[id] = pending
                    if let partial = pending.partial { progress?(partial) }
                } else {
                    let generation = UUID()
                    let task = Task { [weak self, provider] in
                        let result: Result<Conversation, Error>
                        do {
                            result = .success(
                                try await provider.getConversation(
                                    id: id,
                                    progress: { [weak self] partial in
                                        self?.publish(id, generation: generation, partial: partial)
                                    }))
                        } catch { result = .failure(error) }
                        self?.finish(id, generation: generation, result: result)
                    }
                    loading[id] = Pending(
                        generation: generation, task: task, waiters: [waiter: continuation],
                        progress: progress.map { [waiter: $0] } ?? [:], partial: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id, waiter: waiter) }
        }
    }
    private func publish(_ id: String, generation: UUID, partial: Conversation) {
        guard var pending = loading[id], pending.generation == generation else { return }
        pending.partial = partial
        loading[id] = pending
        for callback in pending.progress.values { callback(partial) }
    }
    private func cancel(_ id: String, waiter: UUID) {
        guard var pending = loading[id], let continuation = pending.waiters.removeValue(forKey: waiter) else {
            return
        }
        pending.progress[waiter] = nil
        continuation.resume(throwing: CancellationError())
        if pending.waiters.isEmpty {
            loading[id] = nil
            pending.task.cancel()
        } else {
            loading[id] = pending
        }
    }
    private func finish(_ id: String, generation: UUID, result: Result<Conversation, Error>) {
        guard let pending = loading[id], pending.generation == generation else { return }
        loading[id] = nil
        if case .success(let conversation) = result {
            clock &+= 1
            cache[id] = Cached(
                conversation: conversation,
                bytes: conversation.messages.reduce(0) { $0 + $1.text.utf8.count }, access: clock)
            trim()
            for (owner, callback) in observers where owners[owner] == id { callback(conversation) }
        }
        for continuation in pending.waiters.values { continuation.resume(with: result) }
    }
    private func trim() {
        let pinned = Set(owners.values)
        // Active sources remain shared. Only inactive sources count against the warm cache budget.
        let inactive = cache.filter { !pinned.contains($0.key) }.sorted { $0.value.access < $1.value.access }
        var bytes = inactive.reduce(0) { $0 + $1.value.bytes }
        var count = inactive.count
        for (id, value) in inactive where bytes > byteLimit || count > entryLimit {
            cache[id] = nil
            bytes -= value.bytes
            count -= 1
        }
    }
    public func retainOnly(_ ids: Set<String>) {
        cache = cache.filter { ids.contains($0.key) || owners.values.contains($0.key) }
    }
}
