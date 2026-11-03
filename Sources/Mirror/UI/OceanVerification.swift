import AppKit
import MirrorCore
import QuartzCore

/// Native interaction checks with demo history and isolated state/preferences, never AX grants.
@MainActor enum OceanVerification {
    static func run(_ coordinator: WorkspaceCoordinator) {
        Task {
            do {
                try await verify(coordinator)
                print("OCEAN_PASS themes languages menus find copy typography anchors hide restore setup")
                NSApp.terminate(nil)
            } catch {
                print("OCEAN_FAIL \(error)")
                exit(1)
            }
        }
    }
    private enum Failure: Error { case check(String) }
    private static func require(_ condition: Bool, _ name: String) throws {
        if !condition { throw Failure.check(name) }
    }
    private static func settle() async { try? await Task.sleep(nanoseconds: 250_000_000) }
    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    private static func button(_ root: NSView, _ id: String) throws -> NSButton {
        guard let b = descendants(root).first(where: { $0.identifier?.rawValue == id }) as? NSButton else {
            throw Failure.check("button \(id)")
        }
        return b
    }
    private static func capture(_ window: NSWindow?, _ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["MIRROR_DESIGN_CAPTURES"], let window,
            let view = window.contentView
        else { return }
        if view.subviews.contains(where: { $0 is BlackboardOpening }) {
            // The WindowServer capture includes real compositor animation; cacheDisplay does not.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = [
                "-x", "-o", "-l", String(window.windowNumber),
                URL(fileURLWithPath: directory).appendingPathComponent(name + ".png").path,
            ]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return }
            throw Failure.check("compositor screenshot unavailable")
        }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure.check("bitmap")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure.check("PNG")
        }
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
    private static func verifyAnimationPerformance() async throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let previous = MirrorPreferences.blackboard
        MirrorPreferences.blackboard = true
        defer { MirrorPreferences.blackboard = previous }
        var panels: [NSWindow] = []
        var readers: [ConversationReader] = []
        var openings: [BlackboardOpening] = []
        let conversation = Conversation(
            summary: .init(id: "animation", title: "Synthetic"),
            messages: (0..<30).map {
                Message(id: "a\($0)", role: "assistant", text: "中文 **阅读** English `code`。\n\n动画与字号操作可以同时进行。")
            })
        for index in 0..<4 {
            let panel = NSWindow(
                contentRect: NSRect(x: 50 + index * 70, y: 100 + index * 30, width: 900, height: 490),
                styleMask: [.titled], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            let view = OceanView(frame: panel.contentView!.bounds)
            view.showsBlackboard = true
            let reader = ConversationReader(frame: view.bounds.insetBy(dx: 30, dy: 40))
            view.addSubview(reader)
            panel.contentView = view
            reader.show(conversation, settings: ReadingSettings(), anchor: nil)
            panel.orderFront(nil)
            panel.displayIfNeeded()
            panels.append(panel)
            readers.append(reader)
        }
        defer { for panel in panels { panel.close() } }
        for panel in panels {
            BlackboardOpening.show(in: panel.contentView!)
            guard let opening = panel.contentView!.subviews.compactMap({ $0 as? BlackboardOpening }).first
            else { throw Failure.check("opening layer") }
            try require(
                opening.compositorLayer?.animation(forKey: "position") != nil, "compositor animates wipe")
            openings.append(opening)
        }
        var intervals: [Double] = []
        var last = CACurrentMediaTime()
        var seen = Array(repeating: CGFloat(-1), count: 4)
        var changes = Array(repeating: 0, count: 4)
        for frame in 0..<60 {
            try? await Task.sleep(nanoseconds: 16_666_667)
            let now = CACurrentMediaTime()
            intervals.append((now - last) * 1000)
            last = now
            for index in openings.indices {
                if let position = openings[index].compositorLayer?.presentation()?.position.x,
                    position != seen[index]
                {
                    seen[index] = position
                    changes[index] += 1
                }
            }
            if frame % 8 == 0 {
                for reader in readers { reader.updateFontSize(frame % 16 == 0 ? 22 : 23) }
            }
        }
        intervals.sort()
        let maximum = intervals.last ?? 0
        let p95 = intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
        print(
            "ANIMATION_PERF windows=4 samples=60 presentation_changes=\(changes) sample_p95_ms=\(p95) max_gap_ms=\(maximum)"
        )
        try require(changes.allSatisfy { $0 >= 45 }, "compositor presentation advances")
        try require(maximum <= 50, "animation responsiveness gap <=50ms")
        try? await Task.sleep(nanoseconds: 300_000_000)
        try require(openings.allSatisfy { $0.superview == nil }, "all animation layers finish")
    }
    private static func verifyOpening() async throws {
        let original = MirrorPreferences.blackboard
        MirrorPreferences.blackboard = true
        defer { MirrorPreferences.blackboard = original }
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let view = OceanView(frame: panel.contentView!.bounds)
        view.showsBlackboard = true
        panel.contentView = view
        panel.orderFront(nil)
        defer { panel.close() }
        BlackboardOpening.show(in: view)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        try require(
            view.subviews.contains { $0 is BlackboardOpening } == !reduced, "opening respects reduced motion")
        try capture(panel, "opening-start")
        panel.setContentSize(NSSize(width: 640, height: 360))
        await settle()
        try capture(panel, "opening-resized")
        await settle()
        try capture(panel, "opening-diagonal-middle")
        for opening in view.subviews.compactMap({ $0 as? BlackboardOpening }) { opening.skip() }
        try require(!view.subviews.contains { $0 is BlackboardOpening }, "opening skip removes overlay")
        for kind in [NSEvent.EventType.keyDown, .leftMouseDown] {
            BlackboardOpening.show(in: view)
            let event: NSEvent?
            if kind == .keyDown {
                event = NSEvent.keyEvent(
                    with: kind, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false,
                    keyCode: 7)
            } else {
                event = NSEvent.mouseEvent(
                    with: kind, location: NSPoint(x: 10, y: 10), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
            }
            guard let event else { throw Failure.check("opening input event") }
            NSApp.postEvent(event, atStart: true)
            await settle()
            try require(!view.subviews.contains { $0 is BlackboardOpening }, "native input skips opening")
        }
        BlackboardOpening.show(in: view)
        try? await Task.sleep(nanoseconds: 1_350_000_000)
        try require(!view.subviews.contains { $0 is BlackboardOpening }, "opening finishes fully")
        BlackboardOpening.show(in: view)
        panel.close()
        try require(!view.subviews.contains { $0 is BlackboardOpening }, "closing cancels opening")
        MirrorPreferences.blackboard = false
        BlackboardOpening.show(in: view)
        try require(!view.subviews.contains { $0 is BlackboardOpening }, "classic has no opening")
    }
    private static func verify(_ coordinator: WorkspaceCoordinator) async throws {
        try await verifyOpening()
        try await verifyAnimationPerformance()
        let pasteboard = NSPasteboard.general
        let savedClipboard = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            let items = savedClipboard.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        let originalLanguage = MirrorPreferences.language
        let originalAppearance = MirrorPreferences.appearance
        let originalStyle = MirrorPreferences.blackboard
        defer {
            MirrorPreferences.language = originalLanguage
            MirrorPreferences.appearance = originalAppearance
            MirrorPreferences.blackboard = originalStyle
        }
        for ref in Array(coordinator.windows.values) { ref.close() }
        let workspace = WorkspaceState(
            providerID: "demo", hostBundleID: "fixture", hostTitle: "Ocean verification")
        coordinator.saved.workspaces = [workspace]
        coordinator.lastWorkspace = workspace.id
        let state = ReferenceState(workspaceID: workspace.id, conversationID: "sample")
        coordinator.create(state, focus: true)
        await settle()
        await settle()
        guard let ref = coordinator.windows[state.id] else { throw Failure.check("reference") }
        await settle()
        await settle()
        ref.window?.setContentSize(NSSize(width: 1120, height: 590))
        ref.surface.layoutSubtreeIfNeeded()
        try require(BlackboardMaterial.image != nil, "bundled board texture")
        try require(
            BlackboardMaterial.font(size: 23).fontName.contains("MaShanZheng"), "bundled reading font")
        try capture(ref.window, "blackboard-reading")
        ref.surface.moreButton.performClick(nil)
        await settle()
        try capture(ref.window, "blackboard-tools")
        ref.surface.dismiss()
        let specimen = Conversation(
            summary: .init(id: "blackboard-specimen", title: "产品规划"),
            messages: [
                Message(id: "specimen-user", role: "用户", text: "# 产品规划\n\n我们希望用户在继续工作时，也能随时看到之前讨论过的方案。"),
                Message(
                    id: "specimen-assistant", role: "助手",
                    text:
                        "第一版先解决三件事：\n\n1. 找到需要参考的**历史对话**。\n2. 放在旁边，随时阅读。\n3. 保持内容清晰，减少来回切换。\n\n## 下一步\n\n先验证**阅读体验**，再完善首次配置流程。"
                ),
            ])
        ref.surface.reader.show(specimen, settings: ref.state.settings, anchor: nil)
        try capture(ref.window, "blackboard-chinese")
        ref.surface.reader.show(DemoProvider().sample, settings: ref.state.settings, anchor: nil)
        ref.window?.setContentSize(NSSize(width: 490, height: 696))
        ref.surface.layoutSubtreeIfNeeded()
        ref.surface.reader.restore(ReadingAnchor(messageID: "detail-4", block: 1, character: 260))
        let saved = ref.surface.reader.anchor
        let prefs = PreferencesWindow()
        prefs.present()
        for opening in prefs.window?.contentView?.subviews.compactMap({ $0 as? BlackboardOpening }) ?? [] {
            opening.skip()
        }
        prefs.present()
        try require(
            !(prefs.window?.contentView?.subviews.contains { $0 is BlackboardOpening } ?? false),
            "preferences reopening does not replay")
        for style in ["classic", "blackboard"] {
            try button(prefs.window!.contentView!, style).performClick(nil)
            await settle()
            try require(MirrorPreferences.blackboard == (style == "blackboard"), "reading style preference")
            try require(ref.surface.reader.anchor == saved, "reading style preserves anchor")
        }
        for language in ["zh", "en"] {
            try button(prefs.window!.contentView!, language).performClick(nil)
            await settle()
            try require(MirrorPreferences.language == language, "language preference persisted")
            try require(
                ref.surface.switchButton.title == (language == "zh" ? "切换会话" : "Conversations"),
                "live translated toolbar")
            for appearance in ["light", "dark", "system"] {
                try button(prefs.window!.contentView!, appearance).performClick(nil)
                await settle()
                try require(MirrorPreferences.appearance == appearance, "appearance preference persisted")
                try require(ref.surface.reader.anchor == saved, "preferences preserve anchor")
                if appearance != "system" {
                    try capture(prefs.window, "preferences-\(language)-\(appearance)")
                    ref.window?.makeKeyAndOrderFront(nil)
                    await settle()
                    try capture(ref.window, "reader-\(language)-\(appearance)")
                }
            }
        }
        prefs.close()
        MirrorPreferences.language = "zh"
        MirrorPreferences.appearance = "light"
        await settle()
        ref.surface.switchButton.performClick(nil)
        await settle()
        try require(
            ref.surface.controlsVisible && ref.surface.controls.mode == .conversations, "switcher trigger")
        try capture(ref.window, "switcher")
        let width = ref.surface.reader.frame.width
        ref.find()
        try require(ref.surface.controls.mode == .find, "find trigger")
        try require(ref.surface.reader.frame.width == width, "overlay never changes reading width")
        ref.surface.controls.search.stringValue = "semantic anchor"
        ref.surface.controls.onSearch?("semantic anchor", false)
        try require(!ref.surface.controls.status.stringValue.contains("没有"), "find matches all history")
        let first = ref.surface.reader.anchor
        try button(ref.surface.controls, "next").performClick(nil)
        try require(ref.surface.reader.anchor != first, "next match changes location")
        try capture(ref.window, "find")
        try button(ref.surface.controls, "clear").performClick(nil)
        try require(ref.surface.reader.anchor == saved, "clear restores original anchor")
        ref.surface.dismiss()
        try require(!ref.surface.controlsVisible, "dismiss overlay")
        try require(ref.window?.firstResponder === ref.surface.findButton, "dismiss restores trigger focus")
        ref.surface.moreButton.performClick(nil)
        await settle()
        try capture(ref.window, "actions")
        for width in [1120.0, 490.0] {
            ref.window?.setContentSize(NSSize(width: width, height: 590))
            ref.surface.layoutSubtreeIfNeeded()
            ref.surface.controls.layoutSubtreeIfNeeded()
            for id in ["refresh", "copy", "smaller", "larger"] {
                try require(
                    (try button(ref.surface.controls, id)).isHidden
                        == (MirrorPreferences.blackboard && width >= 520), "contextual action deduplication")
            }
            try require(!(try button(ref.surface.controls, "duplicate")).isHidden, "other actions retained")
            if width >= 520 { try capture(ref.window, "actions-deduplicated") }
        }
        ref.window?.setContentSize(NSSize(width: 490, height: 696))
        ref.surface.layoutSubtreeIfNeeded()
        for id in [
            "duplicate", "refresh", "copy", "smaller", "larger", "collapse", "preferences", "setup", "close",
            "dismiss",
        ] {
            try require(!(try button(ref.surface.controls, id)).isHidden, "action available: \(id)")
        }
        let source = DemoProvider().sample.messages.first(where: { $0.id == saved?.messageID })!
        try button(ref.surface.controls, "copy").performClick(nil)
        try require(
            NSPasteboard.general.string(forType: .string) == source.text, "copy complete source message")
        let font = ref.state.settings.fontSize
        try button(ref.surface.controls, "larger").performClick(nil)
        try require(ref.state.settings.fontSize == font + 1, "larger action")
        try button(ref.surface.controls, "smaller").performClick(nil)
        try require(ref.state.settings.fontSize == font, "smaller action")
        try button(ref.surface.controls, "duplicate").performClick(nil)
        await settle()
        try require(coordinator.windows.count == 2, "duplicate action")
        try button(ref.surface.controls, "collapse").performClick(nil)
        try require(ref.state.collapsed && ref.window?.isVisible == false, "hide action")
        coordinator.restoreHidden()
        try require(!ref.state.collapsed && ref.window?.isVisible == true, "restore hidden action")
        ref.surface.dismiss()
        ref.window?.makeKeyAndOrderFront(nil)
        ref.surface.showControls(.conversations)
        let table = ref.surface.controls.table
        let otherRow = ref.surface.controls.conversations.firstIndex { $0.id == "other" }!
        table.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        table.sendAction(table.action, to: table.target)
        await settle()
        try require(ref.state.conversationID == "other", "conversation row activates its own ID")
        try require(
            coordinator.windows.values.first { $0.state.id != ref.state.id }?.state.conversationID
                == "sample", "switch leaves sibling unchanged")
        ref.act("refresh")
        await settle()
        try require(
            !ref.isLoading && ref.state.conversationID == "other", "refresh settles without switching source")
        ref.load("sample", anchor: saved)
        await settle()
        ref.surface.controls.setHasMore(true)
        ref.surface.showControls(.actions)
        try require(ref.surface.controls.more.isHidden, "pagination excluded from action keyboard loop")
        ref.surface.showControls(.conversations)
        try require(!ref.surface.controls.more.isHidden, "pagination shown only in switcher")
        ref.surface.controls.setHasMore(false)
        ref.surface.dismiss()
        for width in [280.0, 390.0, 900.0] {
            ref.window?.setContentSize(NSSize(width: width, height: 650))
            ref.surface.layoutSubtreeIfNeeded()
            for b in [ref.surface.switchButton, ref.surface.findButton, ref.surface.moreButton] {
                try require(b.frame.minX >= 0 && b.frame.maxX <= width, "toolbar fits width \(width)")
            }
            ref.surface.showControls(.actions)
            ref.surface.layoutSubtreeIfNeeded()
            try require(ref.surface.controls.frame.width <= width, "controls fit narrow width")
            ref.surface.dismiss()
            await settle()
            try capture(ref.window, "width-\(Int(width))")
        }
        ref.window?.setContentSize(NSSize(width: 490, height: 696))
        ref.surface.layoutSubtreeIfNeeded()
        // Same source text as Figma for visual comparison; production data is never replaced.
        let fixture = Conversation(
            summary: .init(id: "design", title: "产品设计笔记"),
            messages: [
                .init(
                    id: "design-1", role: "产品设计笔记 / 只读参考",
                    text:
                        "# 把上下文留在身边。\n# 让注意力回到眼前。\n\n独立的参考窗口，应该如何工作？\n\n---\n\n## 同一个对话，不同的阅读位置。\n\n参考窗口把需要的信息留在工作旁边。复制一个窗口，就能阅读另一段内容，而不打断眼前的思路。\n\n> 每个窗口记住自己的位置。对话内容仍然保持共享。\n\n## 独立保留的内容\n\n阅读位置、字号和窗口尺寸只属于当前参考。关闭它，不会关闭其他窗口。"
                )
            ])
        ref.surface.reader.show(fixture, settings: ReadingSettings(), anchor: nil)
        for appearance in ["light", "dark"] {
            MirrorPreferences.appearance = appearance
            await settle()
            try capture(ref.window, "figma-reading-\(appearance)")
        }
        var setupState = (cli: true, access: false, host: false)
        var completed = 0
        var requested = 0
        var chosen = 0
        let setup = SetupWindow(
            check: { setupState }, requestPermission: { requested += 1 }, chooseCLI: { chosen += 1 },
            finish: { completed += 1 })
        for language in ["zh", "en"] {
            MirrorPreferences.language = language
            await settle()
            for appearance in ["light", "dark"] {
                MirrorPreferences.appearance = appearance
                setup.present()
                await settle()
                try capture(setup.window, "setup-\(language)-\(appearance)")
            }
        }
        for opening in setup.window?.contentView?.subviews.compactMap({ $0 as? BlackboardOpening }) ?? [] {
            opening.skip()
        }
        setup.present()
        try require(
            !(setup.window?.contentView?.subviews.contains { $0 is BlackboardOpening } ?? false),
            "setup reopening does not replay")
        setupState.access = true
        setupState.host = true
        setup.refresh()
        try require(requested == 0, "setup refresh never requests OS permission")
        let choose = descendants(setup.window!.contentView!).compactMap { $0 as? NSButton }.first {
            $0.title.contains("Choose Codex")
        }!
        choose.performClick(nil)
        try require(chosen == 1, "choose executable callback")
        setup.close()
        setup.close()
        try require(completed == 1, "setup completion once")
        try button(ref.surface.controls, "close").performClick(nil)
        try require(coordinator.windows.count == 1, "close action preserves sibling")
    }
}
