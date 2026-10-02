import AppKit
import MirrorCore

// Documentation only: real production windows, a synthetic provider, isolated preferences/state.
// This executable does not use AppDelegate or start a Codex connection.
@MainActor private final class ReleaseDemo: ConversationProvider {
    let id = "release-demo"
    let conversation = Conversation(
        summary: .init(id: "demo-release", title: "项目上线检查 · 演示对话"),
        messages: [
            .init(
                id: "brief", role: "You · 演示内容",
                text: """
                    # 项目上线前，先确认这些事

                    我们准备发布一个小型项目管理工具。请帮我整理上线条件，以及发布当天的检查顺序。

                    ## 这次发布的范围

                    - 用户可以创建项目、分配任务、查看进度。
                    - 数据导出需要保留原始字段。
                    - 首次使用要有清晰的引导。

                    > 先让已有功能可靠，再决定下一步增加什么。

                    ## 需要一直放在手边的要求

                    任何界面调整都要保留原来的操作入口。出错时，用户应该知道发生了什么，以及下一步可以做什么。
                    """),
            .init(
                id: "checks", role: "Assistant · 演示内容",
                text: """
                    # 发布当天的检查顺序

                    ## 01　先验证核心操作

                    用一个全新的演示账号，完整走一遍创建项目、分配任务和完成任务的流程。

                    | 检查项 | 通过条件 |
                    | --- | --- |
                    | 创建项目 | 保存后重新打开仍然可见 |
                    | 分配任务 | 负责人和截止时间正确 |
                    | 导出数据 | 列名与原始字段一致 |

                    ## 02　再检查异常情况

                    断开网络后重试一次。已有内容应当保留，错误提示应当说明如何恢复。

                    ## 03　记录发布结果

                    保存版本号、测试结果和回退方式。发布说明只写已经交付的能力。
                    """),
            .init(
                id: "followup", role: "You · 演示内容",
                text: """
                    # 把检查清单留在旁边

                    我会继续在主对话里讨论实现。这个参考窗口保留需求，另一个窗口保留发布清单。
                    """),
        ])
    func listConversations(query: String, cursor: String?) async throws -> ConversationPage {
        .init(
            conversations: query.isEmpty || conversation.summary.title.contains(query)
                ? [conversation.summary] : [], nextCursor: nil)
    }
    func getConversation(id: String) async throws -> Conversation { conversation }
    func getCurrentConversation(context: HostContext) async throws -> ConversationSummary? { nil }
}

@MainActor private final class CaptureDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: WorkspaceCoordinator!
    private var stage: NSWindow!
    private var preferences: PreferencesWindow?
    private var setup: SetupWindow?
    private var references: [ReferenceWindow] = []
    private let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await run()
                NSApp.terminate(nil)
            } catch {
                fputs("CAPTURE_FAIL \(error)\n", stderr)
                exit(1)
            }
        }
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 450_000_000) }
    private func capture(_ name: String, window: NSWindow? = nil) throws {
        // Capture only owned view trees for the multiwindow scene. A desktop region can
        // show another app if activation changes, so it is deliberately never recorded.
        if window == nil {
            let scene = NSImage(size: stage.frame.size)
            scene.lockFocus()
            func draw(_ view: NSView, in rect: NSRect) throws {
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw NSError(domain: "Screenshot", code: 2)
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                bitmap.draw(in: rect)
            }
            do {
                try draw(stage.contentView!, in: NSRect(origin: .zero, size: stage.frame.size))
                for ref in references {
                    let frame = ref.window!.frame
                    let view = ref.window!.contentView!.superview!
                    try draw(
                        view,
                        in: NSRect(
                            x: frame.minX - stage.frame.minX,
                            y: frame.minY - stage.frame.minY, width: frame.width, height: frame.height))
                }
                scene.unlockFocus()
            } catch {
                scene.unlockFocus()
                throw error
            }
            guard let tiff = scene.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let png = bitmap.representation(using: .png, properties: [:])
            else { throw NSError(domain: "Screenshot", code: 3) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("CAPTURED \(name) owned-native-views")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var arguments = ["-x", "-l", String(window!.windowNumber)]
        arguments.append(output.appendingPathComponent(name + ".png").path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "Screenshot", code: 1) }
        print("CAPTURED \(name)")
    }
    private func run() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        MirrorPreferences.language = "zh"
        MirrorPreferences.appearance = "light"
        let visible = NSScreen.screens[0].visibleFrame
        let width = min(1200, visible.width - 80)
        let height = min(800, visible.height - 50)
        stage = NSWindow(
            contentRect: NSRect(
                x: visible.midX - width / 2, y: visible.midY - height / 2,
                width: width, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        stage.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 10)
        stage.isReleasedWhenClosed = false
        stage.backgroundColor = Ocean.canvas
        let canvas = OceanView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        canvas.fill = Ocean.canvas
        stage.contentView = canvas
        let heading = NSTextField(labelWithString: "同一个对话，不同的阅读位置。")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.textColor = Ocean.text
        heading.frame = NSRect(x: 32, y: 18, width: width - 64, height: 32)
        canvas.addSubview(heading)
        let caption = NSTextField(labelWithString: "演示数据 · 左边留住需求，右边参考发布清单 · 每个窗口独立滚动")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = Ocean.secondary
        caption.frame = NSRect(x: 32, y: height - 32, width: width - 64, height: 20)
        canvas.addSubview(caption)
        stage.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        coordinator = WorkspaceCoordinator(
            provider: ReleaseDemo(),
            stateURL: output.deletingLastPathComponent().appendingPathComponent("capture-state.json"))
        coordinator.standalone = true
        let workspace = WorkspaceState(providerID: "release-demo", hostBundleID: "demo", hostTitle: "Demo")
        coordinator.saved.workspaces = [workspace]
        coordinator.lastWorkspace = workspace.id
        let first = ReferenceState(workspaceID: workspace.id, conversationID: "demo-release")
        coordinator.create(first, focus: true)
        await settle()
        let left = coordinator.windows[first.id]!
        let copy = left.state.duplicate()
        coordinator.create(copy, focus: true)
        await settle()
        let right = coordinator.windows[copy.id]!
        references = [left, right]
        let referenceWidth = (width - 96) / 2
        let referenceHeight = height - 106
        for (index, ref) in [left, right].enumerated() {
            ref.window!.level = NSWindow.Level(rawValue: stage.level.rawValue + 1)
            ref.window!.setFrame(
                NSRect(
                    x: stage.frame.minX + 32 + CGFloat(index) * (referenceWidth + 32),
                    y: stage.frame.minY + 40, width: referenceWidth, height: referenceHeight), display: true)
            ref.surface.layoutSubtreeIfNeeded()
        }
        left.surface.reader.restore(ReadingAnchor(messageID: "brief"))
        right.surface.reader.restore(ReadingAnchor(messageID: "checks"))
        left.window!.orderFrontRegardless()
        right.window!.makeKeyAndOrderFront(nil)
        await settle()
        try capture("multiwindow-light")
        MirrorPreferences.appearance = "dark"
        stage.backgroundColor = Ocean.canvas
        await settle()
        try capture("multiwindow-dark")
        MirrorPreferences.appearance = "light"
        left.window!.orderOut(nil)
        stage.orderOut(nil)
        right.window!.makeKeyAndOrderFront(nil)
        right.surface.switchButton.performClick(nil)
        await settle()
        try capture("conversations", window: right.window!)
        right.surface.dismiss()
        right.find()
        right.surface.controls.search.stringValue = "发布"
        right.surface.controls.onSearch?("发布", false)
        await settle()
        try capture("find", window: right.window!)
        right.surface.dismiss()
        right.window!.orderOut(nil)
        preferences = PreferencesWindow()
        preferences!.present()
        await settle()
        try capture("preferences", window: preferences!.window!)
        preferences!.close()
        setup = SetupWindow(
            check: { (cli: true, access: false, host: false) },
            requestPermission: {}, chooseCLI: {}, finish: {})
        setup!.present()
        await settle()
        try capture("setup", window: setup!.window!)
        setup!.close()
        for ref in Array(coordinator.windows.values) { ref.close() }
        stage.close()
    }
}

@main private struct ReleaseScreenshots {
    static func main() {
        guard CommandLine.arguments.count == 2,
            ProcessInfo.processInfo.environment["MIRROR_PREFS_SUITE"] != nil
        else {
            fputs("Pass an output directory and isolated MIRROR_PREFS_SUITE.\n", stderr)
            exit(1)
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = CaptureDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
