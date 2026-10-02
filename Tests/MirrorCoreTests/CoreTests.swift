import Foundation
import XCTest

@testable import MirrorCore

final class CoreTests: XCTestCase {
    func testDuplicateCopiesViewStateAndRemainsIndependent() {
        var original = ReferenceState(workspaceID: UUID(), conversationID: "thread")
        original.anchor = ReadingAnchor(messageID: "m1", block: 2, character: 67, offset: 3)
        original.settings.fontSize = 18
        var copy = original.duplicate()
        XCTAssertNotEqual(original.id, copy.id)
        XCTAssertEqual(original.conversationID, copy.conversationID)
        XCTAssertEqual(original.anchor, copy.anchor)
        XCTAssertEqual(original.frame.width, copy.frame.width)
        XCTAssertEqual(original.settings, copy.settings)
        copy.anchor?.character = 900
        copy.conversationID = "other"
        XCTAssertEqual(original.anchor?.character, 67)
        XCTAssertEqual(original.conversationID, "thread")
    }

    func testWorkspaceVisibilityIncludesOwnReferencesOnly() {
        let a = UUID()
        let b = UUID()
        for active in [ActiveContext.host(a), .reference(a)] {
            XCTAssertTrue(WorkspaceVisibility.shouldShow(workspaceID: a, active: active, hostAvailable: true))
            XCTAssertFalse(
                WorkspaceVisibility.shouldShow(workspaceID: b, active: active, hostAvailable: true))
            XCTAssertFalse(
                WorkspaceVisibility.shouldShow(workspaceID: a, active: active, hostAvailable: false))
        }
        XCTAssertFalse(
            WorkspaceVisibility.shouldShow(workspaceID: a, active: .unrelated, hostAvailable: true))
    }

    func testPersistenceRoundtripExcludesConversationContent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = JSONStateStorage(url: folder.appendingPathComponent("state.json"))
        XCTAssertEqual(try storage.load(), SavedState())
        var state = SavedState()
        let workspace = WorkspaceState(providerID: "codex", hostBundleID: "test", hostTitle: "Host")
        state.workspaces = [workspace]
        var reference = ReferenceState(workspaceID: workspace.id, conversationID: "thread")
        reference.anchor = ReadingAnchor(messageID: "message", character: 100)
        state.references = [reference, reference.duplicate()]
        try storage.save(state)
        XCTAssertEqual(try storage.load(), state)
        let raw = try String(contentsOf: storage.url, encoding: .utf8)
        XCTAssertFalse(raw.contains("messages"))
        XCTAssertFalse(raw.contains("text"))
        let permissions =
            try FileManager.default.attributesOfItem(atPath: storage.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testCorruptOrFutureStateIsNotSilentlyReset() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = JSONStateStorage(url: folder.appendingPathComponent("state.json"))
        var state = SavedState()
        state.version = 999
        try storage.save(state)
        XCTAssertThrowsError(try storage.load())
        try Data("broken".utf8).write(to: storage.url)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try String(contentsOf: storage.url, encoding: .utf8), "broken")
    }

    func testDanglingWorkspaceIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = JSONStateStorage(url: folder.appendingPathComponent("state.json"))
        var state = SavedState()
        state.references = [.init(workspaceID: UUID())]
        try storage.save(state)
        XCTAssertThrowsError(try storage.load())
    }

    func testCodexDecoderPreservesOrdinaryAndUnknownContent() throws {
        let source =
            #"[{"id":"t1","itemsView":"full","items":[{"id":"u","type":"userMessage","content":[{"type":"text","text":"你好"},{"type":"text","text":"Second paragraph"}]},{"id":"a","type":"agentMessage","text":"Answer"},{"id":"tool","type":"futureTool","result":{"text":"Do not lose me"}}]}]"#
        let turns = try JSONDecoder().decode([JSONValue].self, from: Data(source.utf8))
        let messages = try CodexDecoder.messages(turns)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].text, "你好\n\nSecond paragraph")
        XCTAssertEqual(messages[1].text, "Answer")
        XCTAssertTrue(messages[2].text.contains("Do not lose me"))
        XCTAssertEqual(try CodexDecoder.messages(turns + turns).count, 3)
    }

    func testCodexRejectsSummaryAsFullHistory() throws {
        let source = #"[{"id":"turn","itemsView":"summary","items":[]}]"#
        let turns = try JSONDecoder().decode([JSONValue].self, from: Data(source.utf8))
        XCTAssertThrowsError(try CodexDecoder.messages(turns))
    }

    func testMutationMethodsCannotBeCalled() {
        for method in ["thread/start", "thread/resume", "thread/fork", "turn/start", "thread/archive"] {
            XCTAssertFalse(ReadOnlyRPC.methods.contains(method))
        }
    }

    func testMarkdownFencesTablesAndUnclosedCodeKeepContent() {
        let blocks = MarkdownBlocks.parse(
            "# Heading\n\nText\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n````swift\n```nested\n````\n\n```\nunfinished"
        )
        XCTAssertEqual(blocks[0], .heading("Heading", 1))
        XCTAssertTrue(blocks.contains(.table([["A", "B"], ["1", "2"]])))
        XCTAssertTrue(blocks.contains(.code("```nested", "swift")))
        XCTAssertEqual(blocks.last, .code("unfinished", ""))
    }

    @MainActor func testStoreDeduplicatesConcurrentReads() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: TestProvider())
        let shared = ConversationStore(provider: provider)
        async let first = shared.conversation("thread")
        async let second = shared.conversation("thread")
        let (a, b) = try await (first, second)
        XCTAssertTrue(a === b)
        XCTAssertEqual(provider.reads, 1)
        let c = try await shared.conversation("thread")
        XCTAssertTrue(c === a)
        _ = try await store.conversation("thread")
        shared.retainOnly([])
        _ = try await shared.conversation("thread")
        XCTAssertEqual(provider.reads, 2)
    }
    @MainActor func testCancellingOneSharedWaiterKeepsOtherAlive() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: provider)
        let a = Task { try await store.conversation("shared") }
        let b = Task { try await store.conversation("shared") }
        while store.pendingCount == 0 { await Task.yield() }
        await Task.yield()
        a.cancel()
        do {
            _ = try await a.value
            XCTFail("cancelled waiter published")
        } catch is CancellationError {} catch { XCTFail("wrong cancellation") }
        let result = try await b.value
        XCTAssertEqual(result.summary.id, "shared")
        XCTAssertEqual(provider.reads, 1)
        XCTAssertEqual(store.pendingCount, 0)
    }

    @MainActor func testCancelledLastWaiterCannotRepopulateCache() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: provider)
        let task = Task { try await store.conversation("abandoned") }
        while provider.reads == 0 { await Task.yield() }
        task.cancel()
        _ = await task.result
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(store.cachedCount, 0)
        _ = try await store.conversation("abandoned")
        XCTAssertEqual(provider.reads, 2)
    }

    @MainActor func testWarmCacheIsBoundedAndRefreshReplacesSnapshot() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: provider, entryLimit: 2)
        let owner = UUID()
        store.hold("pinned", owner: owner)
        let pinned = try await store.conversation("pinned")
        for id in ["a", "b", "c", "d"] { _ = try await store.conversation(id) }
        XCTAssertEqual(store.cachedCount, 3)
        let same = try await store.conversation("pinned")
        XCTAssertTrue(same === pinned)
        let refreshed = try await store.conversation("pinned", refresh: true)
        XCTAssertFalse(refreshed === pinned)
        store.release(owner: owner)
        XCTAssertEqual(store.cachedCount, 2)
    }

    @MainActor func testRefreshNotifiesActiveSiblingAndReleaseUnsubscribes() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: provider)
        let owner = UUID()
        var updates = 0
        store.observe(owner: owner) { _ in updates += 1 }
        store.hold("shared", owner: owner)
        _ = try await store.conversation("shared")
        _ = try await store.conversation("shared", refresh: true)
        XCTAssertEqual(updates, 2)
        store.release(owner: owner)
        _ = try await store.conversation("shared", refresh: true)
        XCTAssertEqual(updates, 2)
    }

    @MainActor func testCachedSnapshotRemainsAvailableDuringSharedRefresh() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: provider)
        let original = try await store.conversation("shared")
        provider.delay = 100_000_000
        let first = Task { try await store.conversation("shared", refresh: true) }
        let second = Task { try await store.conversation("shared", refresh: true) }
        while store.pendingCount == 0 { await Task.yield() }
        let cached = try await store.conversation("shared")
        XCTAssertTrue(cached === original)
        first.cancel()
        do {
            _ = try await first.value
            XCTFail("cancelled")
        } catch is CancellationError {}
        let updated = try await second.value
        XCTAssertFalse(updated === original)
        XCTAssertEqual(provider.reads, 2)
        XCTAssertEqual(store.pendingCount, 0)
    }

    @MainActor func testFailedRefreshRetainsLastCompleteCacheAndDoesNotNotify() async throws {
        let provider = TestProvider()
        let store = ConversationStore(provider: provider)
        let owner = UUID()
        var updates = 0
        store.hold("shared", owner: owner)
        store.observe(owner: owner) { _ in updates += 1 }
        let original = try await store.conversation("shared")
        provider.fail = true
        do {
            _ = try await store.conversation("shared", refresh: true)
            XCTFail("expected failure")
        } catch is TestProvider.Failure {}
        let cached = try await store.conversation("shared")
        XCTAssertTrue(cached === original)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(store.pendingCount, 0)
    }

    func testWorkspaceStateMachineFailsClosedAndIsolatesGroups() {
        let a = UUID()
        let b = UUID()
        XCTAssertEqual(
            WorkspacePhase.resolve(workspaceID: a, active: .host(a), availability: .available), .hostActive)
        XCTAssertEqual(
            WorkspacePhase.resolve(workspaceID: a, active: .reference(a), availability: .available),
            .ownedReferenceActive)
        XCTAssertEqual(
            WorkspacePhase.resolve(workspaceID: b, active: .reference(a), availability: .available), .inactive
        )
        for availability in [HostAvailability.minimized, .closed, .unavailable, .restoring, .hidden] {
            XCTAssertFalse(
                WorkspacePhase.resolve(workspaceID: a, active: .host(a), availability: availability).visible)
        }
    }

}

@MainActor private final class TestProvider: ConversationProvider {
    let id = "test"
    var reads = 0
    var delay: UInt64 = 10_000_000
    var fail = false
    enum Failure: Error { case simulated }
    func listConversations(query: String, cursor: String?) async throws -> ConversationPage {
        ConversationPage(conversations: [.init(id: "thread", title: "Title")], nextCursor: nil)
    }
    func getConversation(id: String) async throws -> Conversation {
        reads += 1
        try await Task.sleep(nanoseconds: delay)
        if fail { throw Failure.simulated }
        return Conversation(summary: .init(id: id, title: "Title"), messages: [])
    }
    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary? { nil }
}
