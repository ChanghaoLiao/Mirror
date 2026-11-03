import AppKit

/// This is a guide, not a replacement for the user's macOS permission decision.
@MainActor final class SetupWindow: NSWindowController, NSWindowDelegate {
    private let check: () -> (cli: Bool, access: Bool, host: Bool)
    private let requestPermission: () -> Void
    private let chooseCLI: () -> Void
    private let finish: () -> Void
    private let diagnostics: AccessibilityDiagnostics?
    private var didOpen = false
    private var completed = false
    private var activation: NSObjectProtocol?
    private var preferences: NSObjectProtocol?

    init(
        check: @escaping () -> (cli: Bool, access: Bool, host: Bool),
        requestPermission: @escaping () -> Void, chooseCLI: @escaping () -> Void,
        finish: @escaping () -> Void, diagnostics: AccessibilityDiagnostics? = nil
    ) {
        self.check = check
        self.requestPermission = requestPermission
        self.chooseCLI = chooseCLI
        self.finish = finish
        self.diagnostics = diagnostics
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 690),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Mirror · 初始设置与权限"
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.window?.isVisible == true else { return }
                // Becoming active must not replace the first opening overlay.
                if self.window?.contentView?.subviews.contains(where: { $0 is BlackboardOpening }) != true {
                    self.refresh()
                }
            }
        }
        preferences = NotificationCenter.default.addObserver(
            forName: .mirrorPreferencesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
        if let preferences { NotificationCenter.default.removeObserver(preferences) }
    }
    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !didOpen, let view = window?.contentView {
            didOpen = true
            BlackboardOpening.show(in: view)
        }
    }
    @objc func refresh() {
        let state = check()
        let authorization = diagnostics?.observe(granted: state.access)
        let content = OceanView(frame: NSRect(x: 0, y: 0, width: 570, height: 690))
        content.showsBlackboard = true
        window?.contentView = content
        window?.title = localized("Mirror · Setup & Permissions", "Mirror · 初始设置与权限")
        window?.titlebarAppearsTransparent = true
        window?.backgroundColor = Ocean.subtle
        func label(
            _ text: String, _ y: CGFloat, _ height: CGFloat, _ size: CGFloat = 13, _ bold: Bool = false
        ) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            field.textColor = bold ? Ocean.text : Ocean.secondary
            field.frame = NSRect(x: 32, y: y, width: 506, height: height)
            content.addSubview(field)
        }
        label(localized("Make room for focus.", "让 Mirror 准备好。"), 28, 34, 22, true)
        label(
            localized("Read local conversations. Keep useful context close.", "读取本机对话，把需要的上下文留在身边。"), 76, 40)
        oceanDivider(in: content, y: 120, width: 506)
        oceanDivider(in: content, y: 542, width: 506)
        label(localized("01   Connect Codex", "01   连接本机 Codex"), 138, 26, 16, true)
        label(
            state.cli
                ? localized("Codex found · ready to read local history.", "已找到 Codex · 可以读取本地历史。")
                : localized(
                    "Codex not found. Install it or choose its executable.", "未找到 Codex。请安装或选择本机可执行文件。"), 176,
            40)
        let choose = oceanButton(
            localized("Choose Codex…", "选择 Codex…"), target: self, action: #selector(selectCLI))
        choose.frame = NSRect(x: 32, y: 216, width: 250, height: 32)
        content.addSubview(choose)
        label(localized("02   Window following", "02   窗口跟随"), 278, 26, 16, true)
        let accessStatus: String
        if state.access {
            accessStatus = localized("Accessibility access granted.", "已授权窗口跟随。")
        } else if authorization == .changedDevelopmentBuild {
            accessStatus = localized(
                "This development build differs from the one previously authorized. Access is not active.",
                "当前开发版本与上次授权版本不同，窗口跟随权限未生效。")
        } else if authorization == .previouslyGranted {
            accessStatus = localized(
                "Window-following access is no longer active. Reading still works.",
                "之前获得的窗口跟随权限已失效；仍可阅读对话。")
        } else {
            accessStatus = localized(
                "This copy has no active permission. You can still choose and read conversations.",
                "当前版本尚未获得有效授权；仍可选择和阅读对话。")
        }
        label(accessStatus, 316, 40)
        let permissions = oceanButton(
            state.access ? localized("Authorized", "已授权") : localized("Open System Settings…", "前往系统设置…"),
            target: self,
            action: #selector(openPermissions), primary: !state.access)
        permissions.isEnabled = !state.access
        permissions.frame = NSRect(x: 32, y: 356, width: 250, height: 32)
        content.addSubview(permissions)
        label(
            localized(
                "Enable Mirror in Privacy & Security → Accessibility. If already enabled, remove the old entry and add this exact app again. Find it below.",
                "在「隐私与安全性 → 辅助功能」中开启 Mirror。若已开启仍无效，请移除旧授权项，再添加下方定位的这个应用。"), 402, 46, 11)
        label(localized("03   Choose the host window", "03   选择跟随窗口"), 458, 26, 16, true)
        let host =
            !state.access
            ? localized(
                "After granting access, the Agent can bind a reference for you. Manual binding remains in the Mirror menu.",
                "授权后，Agent 可以为你绑定参考窗；也可从 Mirror 菜单手动绑定。")
            : state.host
                ? localized(
                    "Codex detected. The Agent can bind references automatically, or you can bind from the menu.",
                    "已发现 Codex 窗口。Agent 可自动绑定，也可从菜单手动绑定。")
                : localized(
                    "Open Codex. The Agent can select a unique host; if several windows are open, focus the intended one.",
                    "请打开 Codex，Agent 会选择明确的窗口；存在多个窗口时，请先点击目标窗口。")
        label(host, 496, 46)
        let signingNote =
            diagnostics?.identity.adHoc == true
            ? localized(
                "This development build uses temporary signing; updates may need authorization again.",
                "当前为临时签名开发版，更新后可能需要重新授权。")
            : localized("Keep the app in a stable location.", "请保持应用安装位置固定。")
        label(
            localized(
                "No screen recording, full disk access or API key required. ",
                "无需屏幕录制、完整磁盘访问或 API Key。") + signingNote, 554, 42, 11)
        if diagnostics != nil {
            let reveal = oceanButton(
                localized("Locate this Mirror in Finder", "在 Finder 中定位当前 Mirror"),
                target: self, action: #selector(revealCurrentApplication))
            reveal.frame = NSRect(x: 32, y: 592, width: 330, height: 26)
            reveal.toolTip = diagnostics?.identity.appURL.path
            content.addSubview(reveal)
        }
        let recheck = oceanButton(localized("Check again", "重新检查"), target: self, action: #selector(refresh))
        recheck.frame = NSRect(x: 32, y: 622, width: 160, height: 32)
        content.addSubview(recheck)
        let finish = oceanButton(
            state.cli && state.access
                ? localized("Get started", "开始使用")
                : state.cli ? localized("Continue read-only", "先只读使用") : localized("Set up later", "稍后配置"),
            target: self,
            action: #selector(continueReading), primary: true)
        finish.keyEquivalent = "\r"
        finish.frame = NSRect(x: 200, y: 622, width: 338, height: 32)
        content.addSubview(finish)
    }
    @objc private func selectCLI() { chooseCLI() }
    @objc private func revealCurrentApplication() {
        guard let diagnostics else { return }
        NSWorkspace.shared.activateFileViewerSelecting([diagnostics.identity.appURL])
    }
    @objc private func openPermissions() {
        guard !check().access else {
            refresh()
            return
        }
        requestPermission()
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func continueReading() { close() }
    func windowWillClose(_ notification: Notification) {
        guard !completed else { return }
        completed = true
        finish()
    }
}
