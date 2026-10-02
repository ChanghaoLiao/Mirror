import AppKit
import MirrorCore

@MainActor final class WorkspaceCoordinator {
    let provider: ConversationProvider
    let store: ConversationStore
    let monitor = HostMonitor()
    private let storage: JSONStateStorage
    private var savingEnabled = true
    private var pendingSave: DispatchWorkItem?
    var saved = SavedState()
    var windows: [UUID: ReferenceWindow] = [:]
    var standalone = false
    var lastWorkspace: UUID?
    var report: ((String) -> Void)?
    var startupError: String?
    private var resolutions: [UUID: Task<Void, Never>] = [:]
    private var screenObserver: NSObjectProtocol?
    private(set) var phases: [UUID: WorkspacePhase] = [:]

    init(provider: ConversationProvider, stateURL: URL) {
        self.provider = provider
        store = ConversationStore(provider: provider)
        storage = JSONStateStorage(url: stateURL)
        do { saved = try storage.load() } catch {
            savingEnabled = false
            startupError = localized(
                "State recovery failed. Existing file preserved: \(error.localizedDescription)",
                "窗口恢复失败，已保留原文件：\(error.localizedDescription)")
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for controller in self.windows.values {
                    if let window = controller.window { self.clamp(window) }
                }
            }
        }
        monitor.onChange = { [weak self] in self?.updateVisibility() }
    }

    func restore() {
        for workspace in saved.workspaces { monitor.rebind(workspace) }
        for state in saved.references { create(state, focus: false) }
        lastWorkspace = saved.references.first?.workspaceID
        if standalone || monitor.bindings.isEmpty,
            let first = windows.values.first(where: { !$0.state.collapsed })
        {
            NSApp.activate(ignoringOtherApps: true)
            first.window?.makeKeyAndOrderFront(nil)
            if standalone {
                for reference in windows.values where !reference.state.collapsed {
                    reference.window?.orderFront(nil)
                }
            }
        }
        updateVisibility()
    }

    func open(conversationID: String? = nil, messageID: String? = nil, fromSelection: Bool = false) {
        monitor.refresh()
        let host = monitor.lastHost
        let workspaceID: UUID
        if let key = keyReference {
            workspaceID = key.state.workspaceID
        } else if let host,
            let match = monitor.bindings.first(where: { CFEqual($0.value.element, host.element) })
        {
            workspaceID = match.key
        } else if let host {
            let existing = saved.workspaces.filter {
                $0.hostBundleID == host.bundleID && $0.hostTitle == host.title
                    && monitor.bindings[$0.id] == nil
            }
            if existing.count == 1 {
                workspaceID = existing[0].id
            } else {
                let workspace = WorkspaceState(
                    providerID: provider.id, hostBundleID: host.bundleID, hostTitle: host.title)
                saved.workspaces.append(workspace)
                workspaceID = workspace.id
            }
            monitor.bindings[workspaceID] = host
        } else if standalone, let workspace = saved.workspaces.first {
            workspaceID = workspace.id
        } else {
            // Reading remains usable without AX, but it is visibly not a bound workspace.
            if let workspace = saved.workspaces.first(where: { $0.hostTitle == "Unbound" }) {
                workspaceID = workspace.id
            } else {
                let workspace = WorkspaceState(
                    providerID: provider.id, hostBundleID: "com.openai.codex", hostTitle: "Unbound")
                saved.workspaces.append(workspace)
                workspaceID = workspace.id
            }
        }
        lastWorkspace = workspaceID
        let remembered = saved.workspaces.first(where: { $0.id == workspaceID })?.conversationID
        var state = ReferenceState(workspaceID: workspaceID, conversationID: conversationID ?? remembered)
        if let messageID { state.anchor = ReadingAnchor(messageID: messageID) }
        let offset = Double(windows.count % 8) * 26
        if let screen = NSScreen.main {
            state.frame.x = screen.visibleFrame.maxX - state.frame.width - 35 - offset
            state.frame.y = screen.visibleFrame.maxY - state.frame.height - 35 - offset
        }
        create(state, focus: true)
        if host == nil && !standalone, let reference = windows[state.id] {
            reference.surface.controls.status.stringValue =
                monitor.trusted
                ? localized(
                    "No Codex window selected. Focus Codex, then use Bind to Codex window.",
                    "未选择 Codex 窗口。请先点击 Codex，再从菜单绑定窗口。")
                : localized(
                    "Reading only. Enable host following from Setup & Permissions in Mirror’s menu.",
                    "只读模式。可从 Mirror 菜单的「设置与权限」开启窗口跟随。")
        }
        let referenceID = state.id
        resolutions[referenceID] = Task { [weak self] in
            guard let self, let reference = windows[referenceID], let host else { return }
            let revision = reference.selectionRevision
            defer { resolutions[referenceID] = nil }
            do {
                var resolvedID = reference.state.conversationID
                if conversationID == nil,
                    let current = try await provider.getCurrentConversation(
                        context: HostContext(bundleID: host.bundleID, windowTitle: host.title))
                {
                    guard !Task.isCancelled, windows[referenceID] != nil,
                        reference.selectionRevision == revision
                    else { return }
                    resolvedID = current.id
                    if !fromSelection { reference.load(current.id, anchor: nil) }
                }
                if fromSelection {
                    guard let text = monitor.selectedText(host),
                        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        let id = resolvedID
                    else {
                        reference.surface.showControls()
                        reference.surface.controls.status.stringValue =
                            localized(
                                "Selected text unavailable. Choose a conversation and use Find.",
                                "无法获取所选文字。请选择会话后使用查找。")
                        return
                    }
                    let conversation = try await store.conversation(id)
                    guard !Task.isCancelled, windows[referenceID] != nil,
                        reference.selectionRevision == revision
                    else { return }
                    let matches = conversation.messages.filter { $0.text.contains(text) }
                    guard matches.count == 1 else {
                        reference.surface.showControls()
                        reference.surface.controls.status.stringValue =
                            localized(
                                "Selection is ambiguous. Use Find to choose its occurrence.",
                                "所选文字有多处匹配，请用查找定位。")
                        return
                    }
                    reference.load(id, anchor: ReadingAnchor(messageID: matches[0].id), findText: text)
                }
            } catch {
                guard !Task.isCancelled, windows[referenceID] != nil else { return }
                reference.surface.showControls()
                reference.surface.controls.status.stringValue = error.localizedDescription
            }
        }
    }

    func create(_ state: ReferenceState, focus: Bool) {
        let controller = ReferenceWindow(state: state, store: store, provider: provider)
        windows[state.id] = controller
        if let window = controller.window {
            let frame = NSRect(
                x: state.frame.x, y: state.frame.y, width: state.frame.width, height: state.frame.height)
            window.setFrame(frame, display: true)
            clamp(window)
        }
        controller.onChange = { [weak self] in self?.scheduleSave() }
        controller.onDuplicate = { [weak self] copy in
            self?.create(copy, focus: true)
            self?.scheduleSave()
        }
        controller.onClose = { [weak self] id in
            self?.resolutions.removeValue(forKey: id)?.cancel()
            self?.windows[id] = nil
            if let self {
                self.store.retainOnly(Set(self.windows.values.compactMap { $0.state.conversationID }))
            }
            self?.scheduleSave()
        }
        controller.onActivate = { [weak self, weak controller] in
            self?.lastWorkspace = controller?.state.workspaceID
            DispatchQueue.main.async { [weak self] in self?.updateVisibility() }
        }
        controller.onConversation = { [weak self] id in
            guard let self, let index = saved.workspaces.firstIndex(where: { $0.id == state.workspaceID })
            else { return }
            saved.workspaces[index].conversationID = id
            scheduleSave()
        }
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        scheduleSave()
    }

    private func clamp(_ window: NSWindow) {
        let screen =
            NSScreen.screens.max { a, b in
                let left = a.visibleFrame.intersection(window.frame)
                let right = b.visibleFrame.intersection(window.frame)
                return (left.isNull ? 0 : left.width * left.height)
                    < (right.isNull ? 0 : right.width * right.height)
            } ?? NSScreen.main
        guard let screen else { return }
        let available = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, available.width)
        frame.size.height = min(frame.height, available.height)
        frame.origin.x = min(max(frame.minX, available.minX), available.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, available.minY), available.maxY - frame.height)
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    var keyReference: ReferenceWindow? { windows.values.first { $0.window === NSApp.keyWindow } }

    func bindLastWorkspace() {
        monitor.refresh()
        guard monitor.trusted else {
            report?(
                localized(
                    "macOS has not granted Accessibility to this running version of Mirror. If its switch is already on, quit Mirror, remove its entry in Accessibility settings, then add this app again: \(Bundle.main.bundlePath)",
                    "macOS 尚未给当前版本的 Mirror 授权。如果设置中的开关已经开启，请退出 Mirror，删除辅助功能列表中的 Mirror，再重新添加这个程序：\(Bundle.main.bundlePath)"
                ))
            return
        }
        guard let host = monitor.lastHost else {
            report?(
                localized(
                    "Accessibility is enabled. Mirror has not detected a focused Codex window. Open Codex, click its main window, then try binding again.",
                    "辅助功能权限已生效，但尚未识别到 Codex 窗口。请打开 Codex 并点击它的主窗口，再执行绑定。"))
            return
        }
        guard let id = lastWorkspace,
            let index = saved.workspaces.firstIndex(where: { $0.id == id })
        else {
            report?(
                localized(
                    "Accessibility is enabled and Codex was detected. Open a reference window before binding.",
                    "辅助功能权限已生效，也已识别到 Codex。请先打开一个参考窗口，再执行绑定。"))
            return
        }
        monitor.bindings[id] = host
        saved.workspaces[index].hostTitle = host.title
        saved.workspaces[index].hostBundleID = host.bundleID
        scheduleSave()
        updateVisibility()
    }

    func updateVisibility() {
        guard !standalone else { return }
        for workspace in saved.workspaces { monitor.rebind(workspace) }
        let activeWorkspace = keyReference?.state.workspaceID ?? lastWorkspace
        let active = monitor.currentContext(referenceWorkspace: activeWorkspace)
        if ProcessInfo.processInfo.environment["MIRROR_DEBUG_VISIBILITY"] == "1" {
            print(
                "Mirror visibility: active=\(NSApp.isActive) key=\(keyReference != nil) ax=\(monitor.trusted) foreground=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown") references=\(windows.count)"
            )
            fflush(stdout)
        }
        for controller in windows.values {
            let workspaceID = controller.state.workspaceID
            let unbound = monitor.bindings[workspaceID] == nil
            let phase = WorkspacePhase.resolve(
                workspaceID: workspaceID, active: active, availability: monitor.availability(workspaceID))
            phases[workspaceID] = phase
            controller.window?.subtitle =
                unbound ? localized("Unbound · reading only", "未绑定 · 只读模式") : localizedPhase(phase)
            let ownReference =
                NSApp.isActive
                || NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == ProcessInfo.processInfo.processIdentifier
            let show =
                !controller.state.collapsed
                && (unbound || !monitor.trusted
                    ? ownReference && activeWorkspace == workspaceID
                    : phase.visible)
            if show {
                if controller.window?.isVisible != true { controller.window?.orderFront(nil) }
            } else {
                if controller.window?.isVisible == true { controller.window?.orderOut(nil) }
            }
        }
        if NSApp.isActive, NSApp.keyWindow == nil,
            let reference = windows.values.first(where: {
                $0.state.workspaceID == activeWorkspace && $0.window?.isVisible == true
            })
        {
            reference.window?.makeKey()
        }
    }

    private func localizedPhase(_ phase: WorkspacePhase) -> String {
        let chinese: [WorkspacePhase: String] = [
            .hostActive: "Codex 活跃", .ownedReferenceActive: "参考窗口活跃", .inactive: "未激活",
            .minimized: "Codex 已最小化", .closed: "Codex 已关闭", .unavailable: "窗口跟随不可用", .restoring: "需要绑定窗口",
        ]
        return localized(phase.rawValue, chinese[phase] ?? phase.rawValue)
    }

    func restoreHidden() {
        for controller in windows.values where controller.state.workspaceID == lastWorkspace {
            controller.state.collapsed = false
            controller.window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        updateVisibility()
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func saveNow() {
        pendingSave?.cancel()
        guard savingEnabled else { return }
        for index in saved.workspaces.indices {
            if let host = monitor.bindings[saved.workspaces[index].id] {
                saved.workspaces[index].hostTitle = host.title
            }
        }
        saved.references = windows.values.map(\.state).sorted { $0.id.uuidString < $1.id.uuidString }
        do { try storage.save(saved) } catch {
            report?(
                localized(
                    "Could not save window state: \(error.localizedDescription)",
                    "无法保存窗口状态：\(error.localizedDescription)"))
        }
    }
}
