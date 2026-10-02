import AppKit
import MirrorCore

@MainActor enum UIVerification {
    static func recover(_ coordinator: WorkspaceCoordinator) {
        let expected = coordinator.saved.references
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try check(expected.count == 3, "saved sibling count")
                try check(coordinator.windows.count == expected.count, "restored window count")
                for state in expected {
                    guard let window = coordinator.windows[state.id] else {
                        throw Failure.check("stable window identity")
                    }
                    try check(window.window?.isVisible == true, "restored visible window")
                    try check(window.state.conversationID == state.conversationID, "restored conversation")
                    try check(window.state.anchor == state.anchor, "restored anchor")
                    try check(window.state.frame == state.frame, "restored geometry")
                    try check(window.state.settings == state.settings, "restored reading settings")
                }
                print("RECOVERY_PASS count IDs conversation anchor geometry settings")
                NSApp.terminate(nil)
            } catch {
                print("RECOVERY_FAIL \(error)")
                exit(1)
            }
        }
    }
    static func run(_ coordinator: WorkspaceCoordinator) {
        Task {
            do {
                try stressReader()
                for reference in Array(coordinator.windows.values) { reference.close() }
                let workspace = WorkspaceState(
                    providerID: "demo", hostBundleID: "fixture", hostTitle: "UI Verification")
                coordinator.saved.workspaces = [workspace]
                var state = ReferenceState(workspaceID: workspace.id, conversationID: "sample")
                state.frame.x = 70
                state.frame.y = 150
                coordinator.create(state, focus: true)
                try await Task.sleep(nanoseconds: 800_000_000)
                guard let first = coordinator.windows[state.id] else { throw Failure.check("first window") }
                first.surface.reader.restore(ReadingAnchor(messageID: "detail-4", block: 1, character: 260))
                first.act("duplicate")
                try await Task.sleep(nanoseconds: 800_000_000)
                guard let second = coordinator.windows.values.first(where: { $0.state.id != state.id }) else {
                    throw Failure.check("duplicate")
                }
                try check(first.state.id != second.state.id, "unique view IDs")
                try check(second.state.anchor?.messageID == "detail-4", "duplicate anchor")
                second.surface.reader.search("Reading detail 12")
                try check(first.surface.reader.anchor?.messageID == "detail-4", "independent scroll")
                second.act("duplicate")
                try await Task.sleep(nanoseconds: 800_000_000)
                try check(coordinator.windows.count == 3, "recursive duplicate")
                let third = coordinator.windows.values.first {
                    $0.state.id != first.state.id && $0.state.id != second.state.id
                }!
                third.load("sample", anchor: nil)
                third.load("other", anchor: nil)
                try await Task.sleep(nanoseconds: 500_000_000)
                try check(
                    first.state.conversationID == "sample" && third.state.conversationID == "other",
                    "independent conversation")
                third.act("duplicate")
                try await Task.sleep(nanoseconds: 300_000_000)
                try check(coordinator.windows.count == 4, "four independent windows")
                try check(coordinator.windows.values.allSatisfy { !$0.isLoading }, "all reads settled")
                let before = first.surface.reader.anchor
                first.window?.setContentSize(NSSize(width: 300, height: 500))
                first.surface.layoutSubtreeIfNeeded()
                first.surface.reader.layoutSubtreeIfNeeded()
                try check(
                    first.surface.reader.anchor?.messageID == before?.messageID, "resize message anchor")
                try check(
                    first.surface.reader.anchor?.character == before?.character, "resize character anchor")
                let visible = first.surface.reader.visibleAnchor()
                try check(visible?.messageID == before?.messageID, "actual visible message after resize")
                try check(
                    abs((visible?.character ?? -1000) - (before?.character ?? 0)) < 80,
                    "actual visible character after resize")
                let readerWidth = first.surface.reader.frame.width
                first.surface.showControls()
                first.surface.layoutSubtreeIfNeeded()
                try check(first.surface.reader.frame.width == readerWidth, "overlay does not reflow content")
                first.surface.dismiss()
                first.window?.setContentSize(NSSize(width: 490, height: 650))
                first.surface.reader.restore(ReadingAnchor(messageID: "requirements"))
                first.surface.layoutSubtreeIfNeeded()
                if let bitmap = first.surface.bitmapImageRepForCachingDisplay(in: first.surface.bounds) {
                    first.surface.cacheDisplay(in: first.surface.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]),
                        let path = ProcessInfo.processInfo.environment["MIRROR_SCREENSHOT_PATH"]
                    {
                        try png.write(to: URL(fileURLWithPath: path))
                    }
                }
                first.close()
                try check(coordinator.windows.count == 3, "close does not close siblings")
                for _ in 0..<20 {
                    var transient: ReferenceWindow?
                    let temporary = ReferenceState(workspaceID: workspace.id, conversationID: "sample")
                    coordinator.create(temporary, focus: false)
                    transient = coordinator.windows[temporary.id]
                    weak var released: ReferenceWindow?
                    released = transient
                    transient?.close()
                    transient = nil
                    try await Task.sleep(nanoseconds: 20_000_000)
                    try check(released == nil, "closed reference released")
                }
                try check(coordinator.store.pendingCount == 0, "closed requests released")
                try check(coordinator.windows.count == 3, "repeated close keeps siblings")
                coordinator.saveNow()
                print(
                    "UI_PASS four-windows latest-switch-wins open duplicate recursive-duplicate independent-scroll switch-conversation resize-character-anchor overlay close persist 20-close-release"
                )
                NSApp.terminate(nil)
            } catch {
                print("UI_FAIL \(error)")
                exit(1)
            }
        }
    }
    private static func stressReader() throws {
        let source = DemoProvider().sample.messages
        let messages = (0..<720).map { index in
            Message(
                id: "long-\(index)", role: source[index % source.count].role,
                text: source[index % source.count].text)
        }
        let conversation = Conversation(summary: .init(id: "long", title: "Long fixture"), messages: messages)
        let panel = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 490, height: 650), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let reader = ConversationReader(frame: NSRect(x: 0, y: 0, width: 490, height: 650))
        panel.contentView = reader
        reader.show(conversation, settings: ReadingSettings(), anchor: nil)
        var maximum: Double = 0
        var maximumViews = 0
        for index in stride(from: 16, to: 710, by: 23) {
            let start = ProcessInfo.processInfo.systemUptime
            reader.restore(ReadingAnchor(messageID: "long-\(index)", block: 0))
            panel.displayIfNeeded()
            maximum = max(maximum, (ProcessInfo.processInfo.systemUptime - start) * 1000)
            maximumViews = max(maximumViews, reader.realizedBlockCount)
            try check(reader.visibleAnchor()?.messageID == "long-\(index)", "virtualized jump keeps message")
            try check(reader.realizedBlockCount < 100, "native view count bounded")
            let positions = reader.documentView?.subviews.map { $0.frame.minY } ?? []
            try check(positions == positions.sorted(), "accessibility subviews follow reading order")
        }
        reader.restore(ReadingAnchor(messageID: "long-4", block: 1, character: 260))
        let saved = reader.anchor
        for width in [280.0, 900.0, 490.0] {
            panel.setContentSize(NSSize(width: width, height: 650))
            reader.layoutSubtreeIfNeeded()
            try check(
                reader.visibleAnchor()?.messageID == saved?.messageID, "virtualized resize keeps message")
            try check(
                abs((reader.visibleAnchor()?.character ?? 0) - 260) < 80, "virtualized resize keeps character"
            )
        }
        var larger = ReadingSettings()
        larger.fontSize = 20
        reader.show(conversation, settings: larger, anchor: saved)
        try check(reader.visibleAnchor()?.messageID == saved?.messageID, "font reflow anchor")
        var notice = ""
        reader.onNotice = { notice = $0 }
        reader.restore(ReadingAnchor(messageID: "deleted-message"))
        try check(!notice.isEmpty, "deleted anchor has visible explanation")
        print(
            "VIRTUAL_PASS messages=720 jumps=31 max_jump_display_ms=\(maximum) max_realized=\(maximumViews) resize font missing-anchor"
        )
    }

    private static func check(_ condition: Bool, _ name: String) throws {
        if !condition { throw Failure.check(name) }
    }
    private enum Failure: Error { case check(String) }
}
