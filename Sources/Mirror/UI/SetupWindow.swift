import AppKit

/// This is a guide, not a replacement for the user's macOS permission decision.
@MainActor final class SetupWindow: NSWindowController, NSWindowDelegate {
    private let check: () -> (cli: Bool, access: Bool, host: Bool)
    private let requestPermission: () -> Void
    private let chooseCLI: () -> Void
    private let finish: () -> Void
    private var completed = false
    private var activation: NSObjectProtocol?
    private var preferences: NSObjectProtocol?

    init(
        check: @escaping () -> (cli: Bool, access: Bool, host: Bool),
        requestPermission: @escaping () -> Void, chooseCLI: @escaping () -> Void,
        finish: @escaping () -> Void
    ) {
        self.check = check
        self.requestPermission = requestPermission
        self.chooseCLI = chooseCLI
        self.finish = finish
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 690),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Mirror · 初始设置与权限"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in if self?.window?.isVisible == true { self?.refresh() } }
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
    }
    @objc func refresh() {
        let state = check()
        let content = OceanView(frame: NSRect(x: 0, y: 0, width: 570, height: 690))
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
        label(
            state.access
                ? localized("Accessibility access granted.", "已授权窗口跟随。")
                : localized(
                    "Not authorized. You can still choose and read conversations.", "尚未授权；不影响手动选择与阅读对话。"),
            316, 40)
        let permissions = oceanButton(
            state.access ? localized("Authorized", "已授权") : localized("Open System Settings…", "前往系统设置…"),
            target: self,
            action: #selector(openPermissions), primary: !state.access)
        permissions.isEnabled = !state.access
        permissions.frame = NSRect(x: 32, y: 356, width: 250, height: 32)
        content.addSubview(permissions)
        label(
            localized(
                "Enable Mirror in Privacy & Security → Accessibility. Checked again when you return.",
                "在「隐私与安全性 → 辅助功能」中开启 Mirror，返回后自动检查。"), 402, 42, 11)
        label(localized("03   Choose the host window", "03   选择跟随窗口"), 458, 26, 16, true)
        let host =
            !state.access
            ? localized(
                "After granting access, focus Codex and choose Bind to Codex window from the menu.",
                "授权后点击一次 Codex 窗口，再从菜单选择「绑定 Codex 窗口」。")
            : state.host
                ? localized(
                    "Codex window detected. Bind it from the menu after starting.", "已发现 Codex 窗口。开始后可从菜单绑定。")
                : localized(
                    "Open and focus a Codex window, then bind it from Mirror’s menu.",
                    "请打开并点击一次 Codex 窗口，再从 Mirror 菜单绑定。")
        label(host, 496, 46)
        label(
            localized(
                "No screen recording, full disk access or API key required. Keep the app in a stable location; development rebuilds may need authorization again.",
                "不需要屏幕录制、完整磁盘访问或 API Key。建议固定应用位置；开发版重新编译后可能需要重新授权。"), 554, 42, 11)
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
