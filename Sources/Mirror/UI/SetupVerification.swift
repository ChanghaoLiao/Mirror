import AppKit

@MainActor enum SetupVerification {
    static func run() { Task { await verify() } }
    private static func verify() async {
        let originalLanguage = MirrorPreferences.language
        MirrorPreferences.language = "zh"
        defer { MirrorPreferences.language = originalLanguage }
        var state = (cli: false, access: false, host: false)
        var requested = 0
        var completed = 0
        let setup = SetupWindow(
            check: { state }, requestPermission: { requested += 1 }, chooseCLI: {}, finish: { completed += 1 }
        )
        func contains(_ text: String) -> Bool {
            setup.window?.contentView?.subviews.contains {
                ($0 as? NSTextField)?.stringValue.contains(text) == true || ($0 as? NSButton)?.title == text
            } == true
        }
        func require(_ value: Bool, _ name: String) {
            if !value {
                print("SETUP_FAIL \(name)")
                exit(1)
            }
        }
        setup.present()
        try? await Task.sleep(nanoseconds: 300_000_000)
        require(contains("未找到 Codex"), "missing dependency")
        require(contains("稍后配置"), "missing dependency can defer")
        state.cli = true
        setup.refresh()
        require(contains("先只读使用"), "permission optional for reading")
        require(requested == 0, "refresh never requests permission")
        if let path = ProcessInfo.processInfo.environment["MIRROR_SCREENSHOT_PATH"],
            let view = setup.window?.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        {
            view.layoutSubtreeIfNeeded()
            setup.window?.displayIfNeeded()
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        state.access = true
        setup.refresh()
        require(contains("已授权窗口跟随"), "grant reflected by recheck")
        require(contains("请打开并点击一次 Codex"), "missing host is not missing permission")
        state.host = true
        setup.refresh()
        require(contains("已发现 Codex 窗口"), "ready host")
        state.access = false
        setup.refresh()
        require(contains("尚未授权"), "revocation reflected")
        require(requested == 0, "no automatic permission prompts")
        setup.close()
        setup.close()
        require(completed == 1, "finish once on dismissal")
        print("SETUP_PASS missing-cli read-only grant host revocation no-auto-prompt close-once")
        NSApp.terminate(nil)
    }
}
