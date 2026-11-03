import AppKit
import ApplicationServices
import MirrorCore
import XCTest

@testable import Mirror

final class AgentControlTests: XCTestCase {
    @MainActor func testOpenReusesAReferenceAndKeepsItsPositionUnlessAnAnchorIsRequested() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let first = fixture.command("open", conversation: "sample", message: "sample/architecture")
        let id = try XCTUnwrap(first.windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { !reference.isLoading }
        let anchor = reference.surface.reader.anchor
        let second = fixture.command("open", conversation: "sample")
        XCTAssertTrue(second.ok)
        XCTAssertEqual(second.windowID, id)
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
        XCTAssertEqual(reference.surface.reader.anchor, anchor)
        XCTAssertEqual(fixture.provider.reads["sample"], 1)
        XCTAssertEqual(first.binding, "host_not_found")
    }

    @MainActor func testDuplicateIsIndependentAndCloseOnlyRemovesTheRequestedWindow() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let original = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        try await waitUntil { fixture.coordinator.windows[original]?.isLoading == false }
        let duplicate = try XCTUnwrap(fixture.command("duplicate", window: original).windowID)
        XCTAssertNotEqual(original, duplicate)
        XCTAssertEqual(fixture.coordinator.windows.count, 2)
        XCTAssertTrue(fixture.command("font", window: duplicate, font: 22).ok)
        XCTAssertEqual(fixture.coordinator.windows[duplicate]?.state.settings.fontSize, 22)
        XCTAssertEqual(fixture.coordinator.windows[original]?.state.settings.fontSize, 23)
        XCTAssertTrue(fixture.command("close", window: duplicate).ok)
        XCTAssertNil(fixture.coordinator.windows[duplicate])
        XCTAssertNotNil(fixture.coordinator.windows[original])
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
    }

    @MainActor func testRequestReplayDoesNotCreateAnotherWindowAndIDReuseIsRejected() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let request = AgentRequest(
            action: "open", expectedRevision: fixture.coordinator.agentRevision,
            conversationID: "sample", newWindow: true)
        let first = fixture.coordinator.handleAgent(request)
        let replay = fixture.coordinator.handleAgent(request)
        XCTAssertEqual(replay, first)
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
        XCTAssertEqual(fixture.coordinator.agentRevision, first.revision)
        var conflicting = request
        conflicting.conversationID = "other"
        XCTAssertEqual(fixture.coordinator.handleAgent(conflicting).status, "request_id_conflict")
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
        fixture.coordinator.humanDidInteract()
        fixture.coordinator.agentEnabled = false
        XCTAssertEqual(
            fixture.coordinator.handleAgent(request), first,
            "Retrying a receipt after a human override must not execute the request again")
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
    }

    @MainActor func testHumanInteractionInvalidatesAStaleAgentCommand() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let stale = AgentRequest(
            action: "open", expectedRevision: fixture.coordinator.agentRevision,
            conversationID: "sample")
        fixture.coordinator.humanDidInteract()
        let response = fixture.coordinator.handleAgent(stale)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.status, "revision_conflict")
        XCTAssertTrue(fixture.coordinator.windows.isEmpty)
        XCTAssertTrue(fixture.provider.reads.isEmpty)
    }

    @MainActor func testPauseRejectsEveryMutationButAllowsStatusAndList() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let id = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        try await waitUntil { fixture.coordinator.windows[id]?.isLoading == false }
        fixture.coordinator.agentEnabled = false
        let before = fixture.coordinator.agentRevision
        let windowState = try XCTUnwrap(fixture.coordinator.windows[id]?.state)
        for action in AgentRequest.actions.subtracting(["status", "list"]).sorted() {
            let request = AgentRequest(
                action: action, expectedRevision: before,
                windowID: action == "open" ? nil : id,
                conversationID: action == "open" ? "other" : nil,
                query: action == "find" ? "plan" : nil,
                fontSize: action == "font" ? 21 : nil,
                frame: action == "frame" ? WindowFrame() : nil)
            let response = fixture.coordinator.handleAgent(request)
            XCTAssertEqual(response.status, "agent_paused", action)
            XCTAssertFalse(response.ok, action)
            XCTAssertEqual(fixture.coordinator.agentRevision, before, action)
            XCTAssertEqual(fixture.coordinator.windows[id]?.state, windowState, action)
        }
        for action in ["status", "list"] {
            let response = fixture.coordinator.handleAgent(AgentRequest(action: action))
            XCTAssertTrue(response.ok)
            XCTAssertEqual(response.agentEnabled, false)
            XCTAssertEqual(response.windows?.map(\.id), [id])
        }
    }

    @MainActor func testSelectingAConversationByHandWinsOverAPendingAgentLoad() async throws {
        let fixture = try AgentFixture(gated: ["sample"])
        defer { fixture.dispose() }
        let id = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { fixture.provider.reads["sample"] == 1 }
        let oldRevision = fixture.coordinator.agentRevision
        reference.surface.controls.onSelect?("other")
        XCTAssertGreaterThan(fixture.coordinator.agentRevision, oldRevision)
        try await waitUntil { reference.state.conversationID == "other" && !reference.isLoading }
        fixture.provider.publish("sample")
        fixture.provider.release("sample")
        try await waitUntil { fixture.coordinator.store.pendingCount == 0 }
        await Task.yield()
        XCTAssertEqual(reference.state.conversationID, "other")
        XCTAssertEqual(reference.contentStatus, "loaded")
        XCTAssertFalse(reference.agentLoadInProgress)
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
    }

    @MainActor func testClosingByHandPreventsLateLoadCompletionFromRestoringAWindow() async throws {
        let fixture = try AgentFixture(gated: ["sample"])
        defer { fixture.dispose() }
        let id = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { fixture.provider.reads["sample"] == 1 }
        let oldRevision = fixture.coordinator.agentRevision
        reference.act("close")
        XCTAssertGreaterThan(fixture.coordinator.agentRevision, oldRevision)
        XCTAssertTrue(fixture.coordinator.windows.isEmpty)
        fixture.provider.publish("sample")
        fixture.provider.release("sample")
        try await waitUntil { fixture.coordinator.store.pendingCount == 0 }
        await Task.yield()
        XCTAssertTrue(fixture.coordinator.windows.isEmpty)
        let stale = AgentRequest(action: "open", expectedRevision: oldRevision, conversationID: "sample")
        XCTAssertEqual(fixture.coordinator.handleAgent(stale).status, "revision_conflict")
    }

    @MainActor func testHumanActionCancelsAgentRefreshAndPreservesLoadedContent() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let id = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { !reference.isLoading }
        fixture.provider.gated.insert("sample")
        XCTAssertTrue(fixture.command("refresh", window: id).ok)
        try await waitUntil { fixture.provider.reads["sample"] == 2 }
        XCTAssertTrue(reference.isLoading)
        reference.act("collapse")
        XCTAssertFalse(reference.isLoading)
        XCTAssertEqual(reference.contentStatus, "cancelled")
        XCTAssertTrue(reference.state.collapsed)
        XCTAssertEqual(reference.state.conversationID, "sample")
        fixture.provider.release("sample")
        try await waitUntil { fixture.coordinator.store.pendingCount == 0 }
        XCTAssertTrue(reference.state.collapsed)
        XCTAssertEqual(reference.state.conversationID, "sample")
    }

    @MainActor func testInvalidRequestsHaveNoSideEffects() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let revision = fixture.coordinator.agentRevision
        var invalidFrame = WindowFrame()
        invalidFrame.width = 0
        let invalid = [
            AgentRequest(action: "open", expectedRevision: revision),
            AgentRequest(action: "open", expectedRevision: revision, conversationID: "\n"),
            AgentRequest(action: "font", expectedRevision: revision, fontSize: 27),
            AgentRequest(action: "frame", expectedRevision: revision, frame: invalidFrame),
            AgentRequest(action: "find", expectedRevision: revision),
            AgentRequest(action: "delete_conversation", expectedRevision: revision),
        ]
        for request in invalid {
            XCTAssertEqual(fixture.coordinator.handleAgent(request).status, "invalid_arguments")
            XCTAssertEqual(fixture.coordinator.agentRevision, revision)
            XCTAssertTrue(fixture.coordinator.windows.isEmpty)
            XCTAssertTrue(fixture.coordinator.saved.workspaces.isEmpty)
        }
        XCTAssertTrue(fixture.provider.reads.isEmpty)
    }

    @MainActor func testFindFontFrameVisibilityAndRefreshUseTheSelectedReference() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let id = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { !reference.isLoading }
        XCTAssertTrue(fixture.command("find", window: id, query: "中文规划").ok)
        XCTAssertEqual(reference.surface.controls.search.stringValue, "中文规划")
        XCTAssertTrue(reference.surface.controlsVisible)
        XCTAssertEqual(
            reference.surface.reader.findStatus, localized("1 / 1 · Clear to return", "1 / 1 · 清除后返回原位"))
        XCTAssertTrue(fixture.command("font", window: id, font: 19).ok)
        XCTAssertEqual(reference.state.settings.fontSize, 19)
        var frame = WindowFrame()
        frame.x = -100_000
        frame.y = -100_000
        frame.width = 420
        frame.height = 460
        XCTAssertTrue(fixture.command("frame", window: id, frame: frame).ok)
        let actual = try XCTUnwrap(reference.window?.frame)
        XCTAssertEqual(reference.state.frame.x, actual.minX)
        XCTAssertEqual(reference.state.frame.y, actual.minY)
        XCTAssertEqual(reference.state.frame.width, actual.width)
        XCTAssertEqual(reference.state.frame.height, actual.height)
        if !NSScreen.screens.isEmpty {
            XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(actual) })
        }
        XCTAssertTrue(fixture.command("hide", window: id).ok)
        XCTAssertTrue(reference.state.collapsed)
        XCTAssertTrue(fixture.command("show", window: id).ok)
        XCTAssertFalse(reference.state.collapsed)
        XCTAssertTrue(fixture.command("refresh", window: id).ok)
        try await waitUntil { !reference.isLoading }
        XCTAssertEqual(fixture.provider.reads["sample"], 2)
        XCTAssertEqual(reference.contentStatus, "loaded")
    }

    @MainActor func testMultipleMatchingWindowsRequireAnExplicitChoice() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let first = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let second = try XCTUnwrap(fixture.command("open", conversation: "sample", newWindow: true).windowID)
        XCTAssertNotEqual(first, second)
        let revision = fixture.coordinator.agentRevision
        let ambiguous = fixture.command("open", conversation: "sample")
        XCTAssertFalse(ambiguous.ok)
        XCTAssertEqual(ambiguous.status, "ambiguous_window")
        XCTAssertEqual(fixture.coordinator.windows.count, 2)
        XCTAssertEqual(fixture.coordinator.agentRevision, revision)
        let selected = fixture.command("open", window: second, conversation: "sample")
        XCTAssertTrue(selected.ok)
        XCTAssertEqual(selected.windowID, second)
        XCTAssertEqual(fixture.coordinator.windows.count, 2)
    }

    @MainActor func testOpenReusesAReferenceWhileItsNewConversationIsStillLoading() async throws {
        let fixture = try AgentFixture(gated: ["other"])
        defer { fixture.dispose() }
        let id = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { !reference.isLoading }
        XCTAssertTrue(fixture.command("open", window: id, conversation: "other").ok)
        try await waitUntil { fixture.provider.reads["other"] == 1 }
        XCTAssertTrue(reference.isLoading)
        XCTAssertEqual(
            reference.state.conversationID, "sample", "Existing text remains visible during the read")
        let reopened = fixture.command("open", conversation: "other")
        XCTAssertTrue(reopened.ok)
        XCTAssertEqual(reopened.windowID, id)
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
        XCTAssertEqual(fixture.provider.reads["other"], 1)
        fixture.provider.release("other")
        try await waitUntil { !reference.isLoading }
        XCTAssertEqual(reference.state.conversationID, "other")
    }

    @MainActor func testMissingMessageIsReportedWithoutClaimingTheAnchorLoaded() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let id = try XCTUnwrap(
            fixture.command("open", conversation: "sample", message: "sample/missing").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        try await waitUntil { !reference.isLoading }
        XCTAssertEqual(reference.state.conversationID, "sample")
        XCTAssertEqual(reference.contentStatus, "message_not_found")
        let status = fixture.coordinator.handleAgent(AgentRequest(action: "status"))
        XCTAssertEqual(status.windows?.first?.contentStatus, "message_not_found")
        XCTAssertEqual(status.windows?.first?.loading, false)
    }

    @MainActor func testMissingPermissionOrHostDoesNotPretendToBindOrPreventReading() async throws {
        for reason in ["permission_required", "host_not_found", "ambiguous_host"] {
            let fixture = try AgentFixture()
            defer { fixture.dispose() }
            fixture.coordinator.agentHostResolver = { (nil, reason) }
            let opened = fixture.command("open", conversation: "sample")
            let id = try XCTUnwrap(opened.windowID)
            XCTAssertTrue(opened.ok)
            XCTAssertEqual(opened.binding, reason)
            XCTAssertEqual(opened.windows?.first?.bound, false)
            let revision = fixture.coordinator.agentRevision
            let bind = fixture.command("bind", window: id)
            XCTAssertFalse(bind.ok)
            XCTAssertEqual(bind.status, reason)
            XCTAssertEqual(fixture.coordinator.agentRevision, revision)
            try await waitUntil { fixture.coordinator.windows[id]?.isLoading == false }
            XCTAssertEqual(fixture.coordinator.windows[id]?.contentStatus, "loaded")
        }
    }

    @MainActor func testAutomaticBindingUsesTheResolvedHostAndPreservesAnExistingBinding() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let pid = ProcessInfo.processInfo.processIdentifier
        let originalHost = HostWindow(
            element: AXUIElementCreateApplication(pid), pid: pid,
            title: "Synthetic original host", bundleID: "fixture.host")
        fixture.coordinator.agentHostResolver = { (originalHost, "bound") }
        let opened = fixture.command("open", conversation: "sample")
        let id = try XCTUnwrap(opened.windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[id])
        XCTAssertTrue(opened.ok)
        XCTAssertEqual(opened.binding, "bound")
        XCTAssertEqual(opened.windows?.first?.bound, true)
        XCTAssertEqual(
            fixture.coordinator.monitor.bindings[reference.state.workspaceID]?.title,
            "Synthetic original host")
        try await waitUntil { !reference.isLoading }
        let otherHost = HostWindow(
            element: AXUIElementCreateApplication(-1), pid: -1,
            title: "Another synthetic host", bundleID: "fixture.other")
        fixture.coordinator.agentHostResolver = { (otherHost, "bound") }
        let reopened = fixture.command("open", conversation: "sample")
        XCTAssertEqual(reopened.windowID, id)
        XCTAssertEqual(reopened.binding, "bound")
        XCTAssertEqual(
            fixture.coordinator.monitor.bindings[reference.state.workspaceID]?.title,
            "Synthetic original host", "Reopening must respect a binding already chosen for the reference")
        XCTAssertEqual(fixture.coordinator.windows.count, 1)
    }

    @MainActor func testManualUnbindAppliesToTheSharedWorkspaceAndDefeatsAStaleAgentBind() async throws {
        let fixture = try AgentFixture()
        defer { fixture.dispose() }
        let pid = ProcessInfo.processInfo.processIdentifier
        let host = HostWindow(
            element: AXUIElementCreateApplication(pid), pid: pid,
            title: "Synthetic shared host", bundleID: "fixture.host")
        fixture.coordinator.agentHostResolver = { (host, "bound") }
        let first = try XCTUnwrap(fixture.command("open", conversation: "sample").windowID)
        let reference = try XCTUnwrap(fixture.coordinator.windows[first])
        try await waitUntil { !reference.isLoading }
        let second = try XCTUnwrap(fixture.command("duplicate", window: first).windowID)
        let duplicate = try XCTUnwrap(fixture.coordinator.windows[second])
        XCTAssertEqual(reference.state.workspaceID, duplicate.state.workspaceID)
        let before = fixture.coordinator.handleAgent(AgentRequest(action: "list"))
        XCTAssertEqual(before.windows?.filter(\.bound).count, 2)
        let stale = AgentRequest(action: "bind", expectedRevision: before.revision, windowID: second)
        reference.act("unbind")
        let after = fixture.coordinator.handleAgent(AgentRequest(action: "list"))
        XCTAssertEqual(after.windows?.filter(\.bound).count, 0)
        XCTAssertEqual(after.windows?.count, 2)
        XCTAssertNil(fixture.coordinator.monitor.bindings[reference.state.workspaceID])
        XCTAssertEqual(fixture.coordinator.handleAgent(stale).status, "revision_conflict")
        XCTAssertEqual(fixture.coordinator.saved.workspaces.first?.hostTitle, "Unbound")
    }

    @MainActor private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Synthetic operation did not complete within two seconds", file: file, line: line)
        throw AgentTestError.timedOut
    }
}

private enum AgentTestError: Error { case timedOut }

@MainActor private final class AgentFixture {
    let provider = AgentFixtureProvider()
    let coordinator: WorkspaceCoordinator
    let directory: URL

    init(gated: Set<String> = []) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mirror-agent-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        provider.gated = gated
        coordinator = WorkspaceCoordinator(
            provider: provider, stateURL: directory.appendingPathComponent("state.json"))
        coordinator.standalone = true
        coordinator.agentEnabled = true
        coordinator.agentHostResolver = { (nil, "host_not_found") }
    }

    func command(
        _ action: String, window: UUID? = nil, conversation: String? = nil,
        message: String? = nil, query: String? = nil, font: Double? = nil,
        frame: WindowFrame? = nil, newWindow: Bool? = nil
    ) -> AgentResponse {
        coordinator.handleAgent(
            AgentRequest(
                action: action, expectedRevision: coordinator.agentRevision,
                windowID: window, conversationID: conversation, messageID: message,
                query: query, fontSize: font, frame: frame, newWindow: newWindow))
    }

    func dispose() {
        for reference in Array(coordinator.windows.values) { reference.close() }
        provider.releaseAll()
        coordinator.saveNow()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor private final class AgentFixtureProvider: ConversationProvider {
    let id = "synthetic-agent-test"
    var gated: Set<String> = []
    var reads: [String: Int] = [:]
    private var waiting: [String: [CheckedContinuation<Conversation, Error>]] = [:]
    private var progress: [String: [ConversationProgress]] = [:]
    private let conversations = [
        "sample": Conversation(
            summary: .init(id: "sample", title: "Synthetic plan"),
            messages: [
                .init(id: "sample/requirements", role: "You", text: "A small product plan for testing."),
                .init(
                    id: "sample/architecture", role: "Assistant",
                    text: "中文规划: an independent reference window."),
            ]),
        "other": Conversation(
            summary: .init(id: "other", title: "Human choice"),
            messages: [
                .init(
                    id: "other/manual", role: "You", text: "This is the conversation selected by the person.")
            ]),
    ]

    func listConversations(query: String, cursor: String?) async throws -> ConversationPage {
        ConversationPage(conversations: conversations.values.map(\.summary), nextCursor: nil)
    }
    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary? { nil }
    func getConversation(id: String) async throws -> Conversation {
        try await getConversation(id: id, progress: nil)
    }
    func getConversation(id: String, progress callback: ConversationProgress?) async throws -> Conversation {
        reads[id, default: 0] += 1
        guard let conversation = conversations[id] else { throw AgentTestError.timedOut }
        guard gated.contains(id) else { return conversation }
        if let callback { progress[id, default: []].append(callback) }
        // Intentionally finish even after cancellation: late provider replies must not override a person.
        return try await withCheckedThrowingContinuation { waiting[id, default: []].append($0) }
    }
    func publish(_ id: String) {
        guard let conversation = conversations[id] else { return }
        for callback in progress[id] ?? [] { callback(conversation) }
    }
    func release(_ id: String) {
        guard let conversation = conversations[id] else { return }
        for continuation in waiting.removeValue(forKey: id) ?? [] {
            continuation.resume(returning: conversation)
        }
        progress[id] = nil
    }
    func releaseAll() { for id in Array(waiting.keys) { release(id) } }
}
