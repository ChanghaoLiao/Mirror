import AppKit

@MainActor final class PreferencesWindow: NSWindowController {
    private var observer: NSObjectProtocol?
    init() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 620), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        super.init(window: panel)
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: .mirrorPreferencesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    private func rebuild() {
        let focused = (window?.firstResponder as? NSView)?.identifier
        let view = OceanView(frame: NSRect(x: 0, y: 0, width: 490, height: 620))
        window?.contentView = view
        window?.title = localized("Mirror · Appearance & Language", "Mirror · 外观与语言")
        window?.backgroundColor = Ocean.subtle
        func label(
            _ text: String, _ y: CGFloat, _ height: CGFloat, _ size: CGFloat = 13, _ bold: Bool = false
        ) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            field.textColor = bold ? Ocean.text : Ocean.secondary
            field.frame = NSRect(x: 32, y: y, width: 426, height: height)
            view.addSubview(field)
        }
        label(localized("Make Mirror feel like yours", "把 Mirror 调整到你的习惯"), 32, 34, 22, true)
        oceanDivider(in: view, y: 224, width: 426)
        oceanDivider(in: view, y: 398, width: 426)
        label(localized("Appearance", "外观"), 94, 24, 16, true)
        for (i, entry) in [
            ("system", localized("System", "跟随系统")), ("light", localized("Light", "浅色")),
            ("dark", localized("Dark", "深色")),
        ].enumerated() {
            let b = oceanButton(entry.1, target: self, action: #selector(changeAppearance(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(entry.0)
            b.kind = MirrorPreferences.appearance == entry.0 ? .selected : .quiet
            b.setAccessibilityValue(MirrorPreferences.appearance == entry.0 ? 1 : 0)
            b.frame = NSRect(x: 32 + CGFloat(i) * 144, y: 134, width: 138, height: 32)
            view.addSubview(b)
        }
        label("Ocean · 碧海蓝", 186, 20, 11)
        label(localized("Interface language", "界面语言 / Language"), 250, 24, 16, true)
        for (i, entry) in [("zh", "简体中文"), ("en", "English")].enumerated() {
            let b = oceanButton(entry.1, target: self, action: #selector(changeLanguage(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(entry.0)
            b.kind = MirrorPreferences.language == entry.0 ? .selected : .quiet
            b.setAccessibilityValue(MirrorPreferences.language == entry.0 ? 1 : 0)
            b.frame = NSRect(x: 32 + CGFloat(i) * 217, y: 290, width: 209, height: 32)
            view.addSubview(b)
        }
        label(
            localized(
                "Only interface labels change. Your conversations stay in their original language.",
                "仅更改界面语言，不翻译你的对话。"), 346, 46)
        label(localized("Accessibility", "系统辅助设置"), 420, 24, 16, true)
        label(
            localized(
                "Follows macOS Reduce Motion.\nYour windows and reading positions stay in place.",
                "遵循 macOS 的减少动态效果设置。\n切换外观或语言时保留窗口和阅读位置。"), 458, 48)
        let done = oceanButton(
            localized("Done", "完成"), target: self, action: #selector(finish), primary: true)
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 32, y: 550, width: 426, height: 32)
        view.addSubview(done)
        if let focused, let control = view.subviews.first(where: { $0.identifier == focused }) {
            window?.makeFirstResponder(control)
        }
    }
    @objc private func changeAppearance(_ sender: NSButton) {
        MirrorPreferences.appearance = sender.identifier!.rawValue
    }
    @objc private func changeLanguage(_ sender: NSButton) {
        MirrorPreferences.language = sender.identifier!.rawValue
    }
    @objc private func finish() { close() }
}
