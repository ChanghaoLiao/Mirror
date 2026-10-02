import AppKit
import MirrorCore

final class ReferencePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ReferenceSurface: OceanView {
    let reader = ConversationReader(frame: .zero)
    let controls = ReferenceControls(frame: .zero)
    private let overlay = NSScrollView()
    let switchButton = oceanButton("", target: nil, action: nil)
    let findButton = oceanButton("", target: nil, action: nil)
    let moreButton = oceanButton("•••", target: nil, action: nil)
    private let footer = OceanView()
    private let snapshot = NSTextField(labelWithString: "")
    private let activityPanel = OceanView()
    private let activity = NSTextField(wrappingLabelWithString: "")
    private let cancel = oceanButton("", target: nil, action: nil)
    var onDismiss: (() -> Void)?
    var onCancel: (() -> Void)?
    var onFind: (() -> Void)?
    var onWillShowControls: (() -> Void)?
    private weak var trigger: NSView?
    var controlsVisible: Bool { !overlay.isHidden }
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(reader)
        for button in [switchButton, findButton, moreButton] {
            addSubview(button)
            button.target = self
        }
        switchButton.action = #selector(showConversations)
        findButton.action = #selector(showFind)
        moreButton.action = #selector(showActions)
        overlay.documentView = controls
        overlay.hasVerticalScroller = true
        overlay.autohidesScrollers = true
        overlay.drawsBackground = false
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = 12
        overlay.layer?.borderWidth = 1
        overlay.isHidden = true
        footer.fill = Ocean.canvas
        addSubview(footer)
        footer.addSubview(snapshot)
        snapshot.font = .systemFont(ofSize: 11)
        snapshot.textColor = Ocean.secondary
        snapshot.lineBreakMode = .byTruncatingTail
        activityPanel.isHidden = true
        activityPanel.wantsLayer = true
        activityPanel.layer?.cornerRadius = 12
        activityPanel.layer?.borderWidth = 1
        activity.font = .systemFont(ofSize: 12)
        activity.textColor = Ocean.text
        activityPanel.addSubview(activity)
        activityPanel.addSubview(cancel)
        cancel.target = self
        cancel.action = #selector(cancelReading)
        addSubview(activityPanel)
        addSubview(overlay)
        localize()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func localize() {
        switchButton.title = localized("Conversations", "切换会话")
        findButton.title = localized("Find  ⌘F", "查找  ⌘F")
        cancel.title = localized("Cancel reading", "取消读取")
        snapshot.stringValue = localized("Read-only snapshot · refresh manually", "只读快照 · 手动刷新")
        for b in [switchButton, findButton, cancel] { b.setAccessibilityLabel(b.title) }
        moreButton.setAccessibilityLabel(localized("More reference actions", "更多参考操作"))
        moreButton.toolTip = localized("More reference actions", "更多参考操作")
        activity.setAccessibilityLabel(localized("Reading status", "读取状态"))
        controls.localize()
        needsLayout = true
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            overlay.layer?.borderColor = Ocean.border.cgColor
            activityPanel.layer?.borderColor = Ocean.border.cgColor
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Ocean.divider.setFill()
        NSRect(x: 0, y: 47, width: bounds.width, height: 1).fill()
    }
    override func layout() {
        super.layout()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            overlay.layer?.borderColor = Ocean.border.cgColor
            overlay.layer?.shadowColor = NSColor.black.cgColor
            overlay.layer?.shadowOpacity = 0.14
            overlay.layer?.shadowRadius = 14
            overlay.layer?.shadowOffset = CGSize(width: 0, height: -4)
            activityPanel.layer?.borderColor = Ocean.border.cgColor
        }
        reader.frame = NSRect(x: 0, y: 48, width: bounds.width, height: max(0, bounds.height - 84))
        switchButton.frame = NSRect(x: 8, y: 8, width: bounds.width < 350 ? 112 : 132, height: 32)
        findButton.frame = NSRect(x: bounds.width - 144, y: 8, width: 96, height: 32)
        moreButton.frame = NSRect(x: bounds.width - 44, y: 8, width: 36, height: 32)
        footer.frame = NSRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 36)
        snapshot.frame = NSRect(x: 12, y: 10, width: bounds.width - 24, height: 18)
        let width = min(
            controls.mode == .find ? bounds.width - 24 : controls.mode == .conversations ? 390 : 310,
            bounds.width - 24)
        overlay.frame = NSRect(
            x: bounds.width - width - 12, y: 50, width: width,
            height: min(controls.preferredHeight, max(0, bounds.height - 98)))
        controls.frame = NSRect(x: 0, y: 0, width: width, height: controls.preferredHeight)
        activityPanel.frame = NSRect(
            x: 12, y: 54, width: bounds.width - 24, height: cancel.isHidden ? 60 : 94)
        activity.frame = NSRect(x: 12, y: 10, width: bounds.width - 48, height: 44)
        cancel.frame = NSRect(x: 12, y: 56, width: min(180, bounds.width - 48), height: 32)
    }
    func showControls(_ mode: ReferenceControls.Mode = .actions) {
        onWillShowControls?()
        let wasHidden = overlay.isHidden
        controls.mode = mode
        trigger = mode == .find ? findButton : mode == .conversations ? switchButton : moreButton
        overlay.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        if wasHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            overlay.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                overlay.animator().alphaValue = 1
            }
        } else {
            overlay.alphaValue = 1
        }
        if mode == .conversations {
            window?.makeFirstResponder(controls.conversationSearch)
        } else if mode == .find {
            window?.makeFirstResponder(controls.search)
        } else {
            controls.focusFirstAction()
        }
    }
    func setActivity(_ text: String?, cancellable: Bool = false) {
        activity.stringValue = text ?? ""
        activityPanel.isHidden = text == nil
        cancel.isHidden = !cancellable
        needsLayout = true
    }
    func dismissIfOutside(_ event: NSEvent) {
        guard controlsVisible else { return }
        let point = convert(event.locationInWindow, from: nil)
        if point.y >= 48 && !overlay.frame.contains(point) { dismiss() }
    }
    @objc private func cancelReading() { onCancel?() }
    @objc private func showConversations() { showControls(.conversations) }
    @objc private func showFind() { onFind?() }
    @objc private func showActions() {
        if controlsVisible && controls.mode == .actions { dismiss() } else { showControls(.actions) }
    }
    func dismiss() {
        let wasVisible = controlsVisible
        overlay.isHidden = true
        overlay.alphaValue = 1
        if wasVisible { window?.makeFirstResponder(trigger ?? reader) }
        onDismiss?()
    }
}

@MainActor final class ReferenceWindow: NSWindowController, NSWindowDelegate {
    var state: ReferenceState
    let surface = ReferenceSurface(frame: .zero)
    private let store: ConversationStore
    private let provider: ConversationProvider
    private var conversation: Conversation?
    var displayedSnapshot: Conversation? { conversation }
    private var loadGeneration = 0
    private var publishedGeneration = -1
    var selectionRevision: Int { loadGeneration }
    private var loadTask: Task<Void, Never>?
    private var loadingConversationID: String?
    private var refreshingSnapshot = false
    private var selectedMessageID: String?
    private var preferenceObserver: NSObjectProtocol?
    private var closed = false
    private(set) var isLoading = false
    private var queryTask: Task<Void, Never>?
    private var cursor: String?
    private var queryGeneration = 0
    var onChange: (() -> Void)?
    var onClose: ((UUID) -> Void)?
    var onDuplicate: ((ReferenceState) -> Void)?
    var onActivate: (() -> Void)?
    var onConversation: ((String) -> Void)?

    init(state: ReferenceState, store: ConversationStore, provider: ConversationProvider) {
        self.state = state
        self.store = store
        self.provider = provider
        let panel = ReferencePanel(
            contentRect: NSRect(
                x: state.frame.x, y: state.frame.y,
                width: state.frame.width, height: state.frame.height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Mirror"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = Ocean.subtle
        panel.minSize = NSSize(width: 280, height: 260)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = surface
        surface.reader.onAnchor = { [weak self] anchor in
            self?.state.anchor = anchor
            self?.onChange?()
        }
        surface.onWillShowControls = { [weak self] in
            guard let self, !self.surface.controlsVisible else { return }
            var focused = self.window?.firstResponder as? NSView
            while focused != nil, !(focused is ReadingBlock) { focused = focused?.superview }
            self.selectedMessageID = (focused as? ReadingBlock)?.messageID
        }
        surface.onFind = { [weak self] in self?.find() }
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .mirrorPreferencesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.surface.localize()
                if self.conversation == nil && self.state.conversationID == nil { self.showWelcome() }
            }
        }
        surface.onCancel = { [weak self] in self?.cancelLoad() }
        surface.reader.onNotice = { [weak self] text in self?.surface.setActivity(text) }
        surface.controls.onSelect = { [weak self] id in self?.load(id, anchor: nil) }
        surface.controls.onQuery = { [weak self] query in self?.query(query) }
        surface.controls.onSearch = { [weak self] query, next in
            guard let self else { return }
            self.surface.controls.status.stringValue = self.surface.reader.search(query, next: next)
        }
        surface.controls.onAction = { [weak self] action in self?.act(action) }
        store.observe(owner: state.id) { [weak self] updated in
            guard let self, !self.closed, !self.isLoading, self.state.conversationID == updated.summary.id
            else { return }
            self.conversation = updated
            let position = self.surface.reader.anchor
            self.surface.reader.show(
                updated, settings: self.state.settings, anchor: position, preservingSearch: true)
            self.state.anchor = self.surface.reader.anchor
            self.window?.title = updated.summary.title
            self.onChange?()
        }
        query("")
        if let id = state.conversationID {
            load(id, anchor: state.anchor)
        } else {
            showWelcome()
            surface.showControls(.conversations)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func showWelcome() {
        let welcome = Conversation(
            summary: .init(id: "", title: "Mirror"),
            messages: [
                .init(
                    id: "welcome", role: "Mirror",
                    text:
                        localized(
                            "# Make room for focus.\n\nChoose a conversation above to read beside your work. Your main window stays where you left it.\n\n⌘D opens another reference. ⌘F finds text.\n\nDrag the title bar to move this window.",
                            "# 让一段对话陪你工作。\n\n点击上方「切换会话」，选择已有对话，在这里独立阅读。主窗口会留在原来的位置。\n\n⌘D 复制参考窗口，⌘F 查找内容。\n\n拖动标题栏即可移动窗口。"
                        )
                )
            ])
        surface.reader.show(welcome, settings: state.settings, anchor: nil)
    }

    func load(_ id: String, anchor: ReadingAnchor?, refresh: Bool = false, findText: String? = nil) {
        guard !closed else { return }
        if refresh && isLoading && loadingConversationID == id { return }
        let backgroundRefresh = refresh && conversation?.summary.id == id
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        loadingConversationID = id
        refreshingSnapshot = backgroundRefresh
        selectedMessageID = nil
        store.hold(id, owner: state.id)
        surface.setActivity(
            backgroundRefresh
                ? localized(
                    "Updating in the background… Keep reading; reconnection is automatic.",
                    "正在后台更新… 可继续阅读，连接异常会自动恢复。")
                : conversation == nil
                    ? localized("Reading local history…", "正在读取本地对话…")
                    : localized("Loading… Previous conversation remains visible.", "正在读取… 已有内容仍可阅读。"),
            cancellable: true)
        surface.controls.status.stringValue = localized("Reading local history…", "正在读取本地对话…")
        let store = self.store
        loadTask = Task { [weak self] in
            do {
                let conversation = try await store.conversation(
                    id, refresh: refresh,
                    progress: { [weak self] partial in
                        guard !backgroundRefresh, let self, !self.closed, generation == self.loadGeneration,
                            !Task.isCancelled
                        else { return }
                        if let anchor, !partial.messages.contains(where: { $0.id == anchor.messageID }) {
                            return
                        }
                        let position =
                            self.publishedGeneration == generation ? self.surface.reader.anchor : anchor
                        self.conversation = partial
                        self.state.conversationID = id
                        self.surface.controls.currentConversationID = id
                        self.window?.title = partial.summary.title
                        self.surface.reader.show(partial, settings: self.state.settings, anchor: position)
                        self.publishedGeneration = generation
                        self.surface.setActivity(
                            localized(
                                "Loaded \(partial.messages.count) items · reading more…",
                                "已读取 \(partial.messages.count) 条 · 继续读取中…"), cancellable: true)
                    })
                try Task.checkCancellation()
                guard let self, !self.closed, generation == self.loadGeneration else { return }
                self.conversation = conversation
                self.state.conversationID = id
                self.surface.controls.currentConversationID = id
                let position =
                    backgroundRefresh || self.publishedGeneration == generation
                    ? self.surface.reader.anchor : anchor
                self.state.anchor = position
                self.window?.title = conversation.summary.title
                self.surface.setActivity(nil)
                self.surface.reader.show(
                    conversation, settings: self.state.settings, anchor: position,
                    preservingSearch: backgroundRefresh)
                if let findText { self.surface.reader.search(findText) }
                self.surface.controls.status.stringValue =
                    self.surface.reader.findStatus
                    ?? localized(
                        "\(conversation.messages.count) items · local snapshot · ⌘R to update",
                        "\(conversation.messages.count) 条 · 本地快照 · ⌘R 刷新")
                if !backgroundRefresh { self.surface.dismiss() }
                self.isLoading = false
                self.loadingConversationID = nil
                self.refreshingSnapshot = false
                self.loadTask = nil
                self.onConversation?(id)
                self.onChange?()
            } catch {
                guard let self, !self.closed, generation == self.loadGeneration else { return }
                self.isLoading = false
                self.loadingConversationID = nil
                self.refreshingSnapshot = false
                self.loadTask = nil
                if let previous = self.state.conversationID {
                    store.hold(previous, owner: self.state.id)
                } else {
                    store.release(owner: self.state.id, removeObserver: false)
                }
                if error is CancellationError {
                    self.surface.setActivity(nil)
                    return
                }
                self.surface.setActivity(
                    backgroundRefresh
                        ? localized(
                            "Update unavailable. Your previous content remains readable.", "更新暂未成功，已有内容仍可阅读。")
                        : self.publishedGeneration == generation
                            ? localized("Incomplete history. Refresh to retry.", "内容未完整读取。请从更多菜单刷新重试。")
                            : localized("History unavailable. Refresh to retry.", "暂时无法读取对话。请从更多菜单刷新重试。"))
                if !backgroundRefresh { self.surface.showControls() }
                self.surface.controls.status.stringValue = error.localizedDescription
            }
        }
    }

    func cancelLoad() {
        let preserved = refreshingSnapshot
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        loadingConversationID = nil
        refreshingSnapshot = false
        if let id = state.conversationID {
            store.hold(id, owner: state.id)
        } else {
            store.release(owner: state.id, removeObserver: false)
        }
        surface.setActivity(
            preserved
                ? localized("Update cancelled. Your previous content is unchanged.", "更新已取消，已有内容已保留。")
                : localized("Reading cancelled. Displayed content may be incomplete.", "读取已取消。当前显示的内容可能不完整。"))
    }

    private func query(_ query: String, more: Bool = false) {
        queryTask?.cancel()
        queryGeneration += 1
        let generation = queryGeneration
        if !more { cursor = nil }
        let nextCursor = cursor
        queryTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let page = try await provider.listConversations(query: query, cursor: nextCursor)
                guard !Task.isCancelled, generation == queryGeneration else { return }
                surface.controls.conversations =
                    more ? surface.controls.conversations + page.conversations : page.conversations
                cursor = page.nextCursor
                surface.controls.setHasMore(cursor != nil)
                surface.controls.table.reloadData()
                if surface.controls.conversations.isEmpty {
                    surface.controls.status.stringValue = localized(
                        "No conversations found. Try another title.", "没有匹配的会话，请尝试其他标题。")
                }
            } catch is CancellationError { return } catch {
                guard !Task.isCancelled, generation == queryGeneration, !closed else { return }
                surface.controls.status.stringValue = error.localizedDescription
            }
        }
    }

    func act(_ action: String) {
        switch action {
        case "preferences":
            NotificationCenter.default.post(name: .mirrorShowPreferences, object: nil)
        case "setup":
            NotificationCenter.default.post(name: .mirrorShowSetup, object: nil)
        case "duplicate":
            captureFrame()
            state.anchor = surface.reader.anchor
            onDuplicate?(state.duplicate())
        case "copy":
            var focused = window?.firstResponder as? NSView
            while focused != nil, !(focused is ReadingBlock) { focused = focused?.superview }
            let messageID =
                (focused as? ReadingBlock)?.messageID ?? selectedMessageID ?? surface.reader.anchor?.messageID
            if let message = conversation?.messages.first(where: { $0.id == messageID }) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                surface.controls.status.stringValue = localized(
                    "Complete message copied, including source Markdown.", "已复制完整消息，包含原始 Markdown。")
            }
        case "close": close()
        case "collapse":
            state.collapsed = true
            window?.orderOut(nil)
            onChange?()
        case "dismiss": surface.dismiss()
        case "next":
            surface.controls.status.stringValue = surface.reader.search(
                surface.controls.search.stringValue, next: true)
        case "more": query(surface.controls.conversationSearch.stringValue, more: true)
        case "refresh":
            guard !isLoading else { return }
            if let id = state.conversationID { load(id, anchor: surface.reader.anchor, refresh: true) }
            query(surface.controls.conversationSearch.stringValue)
        case "smaller", "larger":
            state.settings.fontSize = min(
                26, max(11, state.settings.fontSize + (action == "larger" ? 1 : -1)))
            if let conversation {
                surface.reader.show(conversation, settings: state.settings, anchor: state.anchor)
            }
            onChange?()
        default: break
        }
    }
    func find() {
        surface.showControls(.find)
        window?.makeFirstResponder(surface.controls.search)
    }
    func captureFrame() {
        guard let window else { return }
        // Store the outer frame consistently; construction restores it after window creation.
        state.frame.x = window.frame.minX
        state.frame.y = window.frame.minY
        state.frame.width = window.frame.width
        state.frame.height = window.frame.height
    }
    func windowDidMove(_ notification: Notification) {
        captureFrame()
        onChange?()
    }
    func windowDidResize(_ notification: Notification) {
        captureFrame()
        onChange?()
    }
    func windowDidBecomeKey(_ notification: Notification) { onActivate?() }
    func windowWillClose(_ notification: Notification) {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        preferenceObserver = nil
        closed = true
        queryTask?.cancel()
        loadTask?.cancel()
        store.release(owner: state.id)
        loadGeneration += 1
        onClose?(state.id)
    }
}
