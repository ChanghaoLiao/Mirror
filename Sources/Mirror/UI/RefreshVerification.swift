import AppKit
import MirrorCore

/// Controlled native windows, using synthetic data only; no system permissions are changed.
@MainActor enum RefreshVerification {
    private enum Failure: Error { case check(String) }
    private static func require(_ value: Bool, _ name: String) throws {
        if !value { throw Failure.check(name) }
    }
    private static func until(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw Failure.check("settle timeout")
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    static func run() {
        Task {
            do {
                try await verify()
                print(
                    "REFRESH_PASS atomic-content live-anchor coalesced-clicks cached-open shared-cancel failure-preserves cold-progress"
                )
                NSApp.terminate(nil)
            } catch {
                print("REFRESH_FAIL \(error)")
                exit(1)
            }
        }
    }
    private static func verify() async throws {
        let provider = RefreshFixtureProvider()
        let store = ConversationStore(provider: provider)
        let workspace = UUID()
        let first = ReferenceWindow(
            state: .init(workspaceID: workspace, conversationID: "sample"), store: store, provider: provider)
        let second = ReferenceWindow(
            state: .init(workspaceID: workspace, conversationID: "sample"), store: store, provider: provider)
        defer {
            first.close()
            second.close()
        }
        first.showWindow(nil)
        second.showWindow(nil)
        first.surface.layoutSubtreeIfNeeded()
        second.surface.layoutSubtreeIfNeeded()
        try await until { !first.isLoading && !second.isLoading }
        try require(provider.reads == 1, "cold requests share source")
        first.surface.reader.restore(.init(messageID: "detail-4", block: 1, character: 260))
        second.surface.reader.restore(.init(messageID: "detail-7", block: 1, character: 140))
        let beforeFind = first.surface.reader.anchor
        first.find()
        first.surface.controls.search.stringValue = "semantic anchor"
        first.surface.controls.onSearch?("semantic anchor", false)
        let original = first.displayedSnapshot
        let secondPosition = second.surface.reader.anchor
        provider.blocked = true
        let revision = first.selectionRevision
        for _ in 0..<25 { first.act("refresh") }
        try await until { provider.pending != nil }
        try require(first.selectionRevision == revision + 1, "rapid refresh clicks coalesce")
        provider.partial()
        try require(
            first.displayedSnapshot === original && second.displayedSnapshot === original,
            "partial never replaces complete snapshot")
        first.surface.reader.restore(.init(messageID: "detail-6", block: 1, character: 180))
        let latestPosition = first.surface.reader.anchor
        provider.complete()
        try await until { !first.isLoading }
        try require(
            first.displayedSnapshot === provider.updated && second.displayedSnapshot === provider.updated,
            "complete snapshot updates siblings")
        try require(
            first.surface.reader.anchor == latestPosition,
            "commit preserves current rather than starting anchor")
        try require(second.surface.reader.anchor == secondPosition, "independent sibling anchor")
        try require(provider.reads == 2, "one refresh source")
        try require(
            first.surface.controlsVisible && first.surface.controls.mode == .find, "refresh keeps find open")
        let found = first.surface.reader.search("semantic anchor", next: true)
        try require(
            !found.contains("No matches") && !found.contains("没有"), "find works after refreshed content")
        first.surface.reader.search("")
        try require(
            first.surface.reader.anchor == beforeFind, "clear preserves pre-find position across refresh")

        first.act("refresh")
        try await until { provider.pending != nil }
        let opened = ReferenceWindow(
            state: .init(workspaceID: workspace, conversationID: "sample"), store: store, provider: provider)
        defer { opened.close() }
        opened.showWindow(nil)
        try await until { !opened.isLoading }
        try require(opened.displayedSnapshot === provider.updated, "cached open does not wait for refresh")
        second.act("refresh")
        await Task.yield()
        first.cancelLoad()
        await Task.yield()
        try require(provider.pending != nil, "cancel one reader preserves shared operation")
        provider.complete()
        try await until { !second.isLoading && store.pendingCount == 0 }
        try require(provider.reads == 3, "shared refresh is not restarted")

        first.act("refresh")
        try await until { provider.pending != nil }
        provider.partial()
        provider.fail()
        try await until { !first.isLoading }
        try require(first.displayedSnapshot === provider.updated, "failed update preserves complete content")
        let cached = try await store.conversation("sample")
        try require(cached === provider.updated, "failed update preserves cache")

        first.act("refresh")
        try await until { provider.pending != nil }
        first.cancelLoad()
        try await until { store.pendingCount == 0 && provider.pending == nil }
        provider.complete()  // Late completion must do nothing after cancellation.
        try require(first.displayedSnapshot === provider.updated, "cancelled update preserves content")

        let coldProvider = RefreshFixtureProvider()
        coldProvider.blocked = true
        let coldStore = ConversationStore(provider: coldProvider)
        let cold = ReferenceWindow(
            state: .init(workspaceID: workspace, conversationID: "sample"), store: coldStore,
            provider: coldProvider)
        defer { cold.close() }
        cold.showWindow(nil)
        try await until { coldProvider.pending != nil }
        coldProvider.partial()
        try require(
            cold.displayedSnapshot?.summary.title == "Partial fixture",
            "cold reads still display progressive content")
        coldProvider.complete()
        try await until { !cold.isLoading }
        try require(cold.displayedSnapshot === coldProvider.updated, "cold read ends complete")
    }
}

@MainActor private final class RefreshFixtureProvider: ConversationProvider {
    let id = "refresh-fixture"
    let original = DemoProvider().sample
    let updated: Conversation
    var reads = 0
    var blocked = false
    var pending: CheckedContinuation<Conversation, Error>?
    private var progress: ConversationProgress?
    private var ticket = UUID()
    init() {
        updated = Conversation(
            summary: .init(id: "sample", title: "Updated fixture"),
            messages: original.messages + [
                .init(id: "updated-tail", role: "assistant", text: "New complete content.")
            ])
    }
    func listConversations(query: String, cursor: String?) async throws -> ConversationPage {
        .init(conversations: [original.summary], nextCursor: nil)
    }
    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary? { nil }
    func getConversation(id: String) async throws -> Conversation {
        try await getConversation(id: id, progress: nil)
    }
    func getConversation(id: String, progress: ConversationProgress?) async throws -> Conversation {
        reads += 1
        if !blocked { return original }
        let current = UUID()
        ticket = current
        self.progress = progress
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { pending = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.ticket == current else { return }
                self.finish(.failure(CancellationError()))
            }
        }
    }
    func partial() {
        progress?(
            Conversation(
                summary: .init(id: "sample", title: "Partial fixture"),
                messages: [
                    .init(
                        id: "partial", role: "assistant",
                        text: "Partial content must not replace a complete snapshot.")
                ]))
    }
    func complete() { finish(.success(updated)) }
    func fail() { finish(.failure(ConnectionError.disconnected)) }
    private func finish(_ result: Result<Conversation, Error>) {
        let waiter = pending
        pending = nil
        progress = nil
        waiter?.resume(with: result)
    }
}
