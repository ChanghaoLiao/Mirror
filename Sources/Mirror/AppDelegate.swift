import AppKit
import MirrorCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: WorkspaceCoordinator!
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?
    private var eventMonitor: Any?
    private var adapter: CodexAdapter?
    private var terminationReady = false
    private var setup: SetupWindow?
    private var preferences: PreferencesWindow?
    private var uiObservers: [NSObjectProtocol] = []
    private var readingStarted = false
    private var pendingURLs: [URL] = []
    private let setupKey = "mirror.setup.v1.seen"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = ProcessInfo.processInfo.arguments
        if args.contains(where: { $0.hasPrefix("--verify") || $0 == "--benchmark" }) { setbuf(stdout, nil) }
        let preview =
            args.contains("--verify-setup") || args.contains("--setup-preview")
            || args.contains("--benchmark") || args.contains("--demo")
            || args.contains("--verify-ui") || args.contains("--verify-ocean")
            || args.contains("--verify-recovery") || args.contains("--verify-refresh")
        let statePath = ProcessInfo.processInfo.environment["MIRROR_STATE_PATH"]
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mirror")
        let stateURL =
            statePath.map { URL(fileURLWithPath: $0) } ?? directory.appendingPathComponent("state.json")
        let provider: ConversationProvider
        if preview {
            provider = DemoProvider()
        } else {
            let codex = CodexAdapter()
            adapter = codex
            provider = codex
        }
        coordinator = WorkspaceCoordinator(provider: provider, stateURL: stateURL)
        coordinator.standalone = preview
        coordinator.report = { [weak self] message in self?.showMessage(message) }
        MirrorPreferences.applyAppearance()
        configureMenu()
        uiObservers = [
            NotificationCenter.default.addObserver(
                forName: .mirrorPreferencesChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.configureMenu() }
            },
            NotificationCenter.default.addObserver(forName: .mirrorShowPreferences, object: nil, queue: .main)
            { [weak self] _ in
                Task { @MainActor in self?.showPreferences() }
            },
            NotificationCenter.default.addObserver(forName: .mirrorShowSetup, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.showSetup() }
            },
        ]
        shortcut = GlobalShortcut()
        shortcut?.onOpen = { [weak self] in self?.openReference() }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) {
            [weak self] event in
            guard let self, let reference = self.coordinator.keyReference else { return event }
            if event.type == .leftMouseDown {
                if event.window === reference.window { reference.surface.dismissIfOutside(event) }
                return event
            }
            if event.keyCode == 53 {
                reference.surface.dismiss()
                return nil
            }
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers {
            case "d": reference.act("duplicate")
            case "f": reference.find()
            case "r": reference.act("refresh")
            case "w": reference.act("close")
            case "n": self.coordinator.open()
            default: return event
            }
            return nil
        }
        if args.contains("--benchmark") {
            PerformanceVerification.run()
            return
        }
        if args.contains("--verify-refresh") {
            RefreshVerification.run()
            return
        }
        if args.contains("--verify-setup") {
            SetupVerification.run()
            return
        }
        if args.contains("--setup-preview") {
            showSetup()
            return
        }
        if !preview, !args.contains("--verify-adapter"), !args.contains("--verify-reliability"),
            !UserDefaults.standard.bool(forKey: setupKey)
        {
            showSetup()
            return
        }
        readingStarted = true
        coordinator.restore()
        if args.contains("--verify-recovery") {
            UIVerification.recover(coordinator)
            return
        }
        if args.contains("--verify-ocean") {
            OceanVerification.run(coordinator)
            return
        }
        if args.contains("--verify-ui") {
            UIVerification.run(coordinator)
            return
        }
        if args.contains("--verify-adapter") || args.contains("--verify-reliability") {
            Task {
                do {
                    if args.contains("--verify-reliability") {
                        try await PerformanceVerification.reliability(provider)
                    } else {
                        try await PerformanceVerification.probe(provider)
                    }
                    await adapter?.connection.disconnect()
                    NSApp.terminate(nil)
                } catch {
                    print("ADAPTER_FAIL \(error.localizedDescription)")
                    await adapter?.connection.disconnect()
                    exit(1)
                }
            }
            return
        }
        if preview, coordinator.windows.isEmpty {
            coordinator.open(conversationID: "sample")
        } else if coordinator.windows.isEmpty {
            coordinator.open()
        }
        if let error = coordinator.startupError { showMessage(error) }
    }

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        main.addItem(appItem)
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: localized("Quit Mirror", "退出 Mirror"), action: #selector(quit), keyEquivalent: "q"
        )
        .target = self
        let editItem = NSMenuItem()
        let edit = NSMenu(title: localized("Edit", "编辑"))
        editItem.title = localized("Edit", "编辑")
        editItem.submenu = edit
        main.addItem(editItem)
        edit.addItem(
            withTitle: localized("Copy", "复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(
            withTitle: localized("Select All", "全选"), action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a")
        NSApp.mainMenu = main
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◧"
        item.button?.toolTip = "Mirror — a second screen for AI conversations"
        let menu = NSMenu()
        for (title, action) in [
            (localized("Open Reference  ⇧⌘M", "打开参考窗口  ⇧⌘M"), #selector(openReference)),
            (localized("Open at selected text", "从所选文字打开"), #selector(openSelection)),
            (localized("Restore hidden references", "恢复隐藏的参考窗口"), #selector(restoreHidden)),
            (localized("Bind to Codex window", "绑定 Codex 窗口"), #selector(bindHost)),
            (localized("Setup & Permissions…", "设置与权限…"), #selector(showSetup)),
            (localized("Choose Codex executable…", "选择 Codex 可执行文件…"), #selector(chooseCodex)),
            (localized("Appearance & Language…", "外观与语言…"), #selector(showPreferences)),
            (localized("About Mirror", "关于 Mirror"), #selector(about)),
            (localized("Quit Mirror", "退出 Mirror"), #selector(quit)),
        ] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        item.menu = menu
        statusItem = item
    }
    @objc private func showPreferences() {
        if preferences == nil { preferences = PreferencesWindow() }
        preferences?.present()
    }
    @objc private func openReference() {
        guard readingStarted else {
            showSetup()
            return
        }
        coordinator.open()
    }
    @objc private func showSetup() {
        if let setup, setup.window?.isVisible == true {
            setup.present()
            return
        }
        let isPreview = ProcessInfo.processInfo.arguments.contains("--setup-preview")
        setup = SetupWindow(
            check: { [weak self] in
                guard let self else { return (false, false, false) }
                if isPreview { return (true, false, false) }
                self.coordinator.monitor.refresh()
                return (
                    CodexInstallation.executablePath != nil, self.coordinator.monitor.trusted,
                    self.coordinator.monitor.lastHost != nil
                )
            }, requestPermission: { [weak self] in self?.coordinator.monitor.requestPermission() },
            chooseCLI: { [weak self] in self?.chooseCodex() },
            finish: { [weak self] in
                guard let self else { return }
                if !isPreview { UserDefaults.standard.set(true, forKey: self.setupKey) }
                guard !self.readingStarted else { return }
                self.readingStarted = true
                self.coordinator.restore()
                let urls = self.pendingURLs
                self.pendingURLs = []
                if !urls.isEmpty {
                    self.application(NSApp, open: urls)
                } else if self.coordinator.windows.isEmpty {
                    self.coordinator.open(conversationID: isPreview ? "sample" : nil)
                }
                if let error = self.coordinator.startupError { self.showMessage(error) }
            })
        setup?.present()
    }
    @objc private func openSelection() {
        if readingStarted { coordinator.open(fromSelection: true) } else { showSetup() }
    }
    @objc private func restoreHidden() {
        if readingStarted { coordinator.restoreHidden() } else { showSetup() }
    }
    @objc private func bindHost() {
        if readingStarted { coordinator.bindLastWorkspace() } else { showSetup() }
    }
    @objc private func chooseCodex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message =
            localized(
                "Select the installed Codex CLI executable. Mirror will use it only to read local history.",
                "选择本机已安装的 Codex 可执行文件，Mirror 仅用它读取历史对话。")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard FileManager.default.isExecutableFile(atPath: url.path), url.lastPathComponent == "codex"
            else {
                self?.showMessage(
                    localized("Select the Codex CLI executable named codex.", "请选择名为 codex 的 Codex 可执行文件。"))
                return
            }
            UserDefaults.standard.set(url.path, forKey: "codexExecutable")
            Task { @MainActor in
                await self?.adapter?.connection.disconnect()
                if self?.setup?.window?.isVisible == true {
                    self?.setup?.refresh()
                } else {
                    self?.showMessage(
                        localized(
                            "Codex location saved. Refresh this reference to reconnect.",
                            "已保存 Codex 位置。刷新参考窗口以重新连接。"))
                }
            }
        }
    }
    @objc private func about() {
        showMessage(
            localized(
                "Mirror 0.2.1\nA second screen for your AI conversations.\n\n⌘D duplicates; ⌘F searches; ⌘R refreshes. History stays local.\n\nWindow following uses Accessibility. Remote images are not fetched.",
                "Mirror 0.2.1\n把对话留在身边的独立参考窗口。\n\n⌘D 复制窗口，⌘F 查找，⌘R 刷新。历史内容保留在本机。\n\n窗口跟随需要辅助功能权限。不会自动下载远程图片。")
        )
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func showMessage(_ message: String) {
        if let reference = coordinator?.keyReference {
            reference.surface.showControls()
            reference.surface.controls.status.stringValue = message
        } else {
            let alert = NSAlert()
            alert.messageText = "Mirror"
            alert.informativeText = message
            alert.addButton(withTitle: localized("OK", "好"))
            alert.runModal()
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard readingStarted else {
            pendingURLs += urls
            showSetup()
            return
        }
        for url in urls where url.scheme == "mirror" && url.host == "open" {
            let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let id = params.first(where: { $0.name == "conversation" })?.value else { continue }
            coordinator.open(
                conversationID: id, messageID: params.first(where: { $0.name == "message" })?.value)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if readingStarted { coordinator?.saveNow() }
        guard let adapter, !terminationReady else { return .terminateNow }
        Task {
            await adapter.connection.disconnect()
            terminationReady = true
            NSApp.terminate(nil)
        }
        return .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !readingStarted {
            showSetup()
        } else if coordinator.windows.isEmpty {
            coordinator.open()
        } else {
            coordinator.restoreHidden()
        }
        return false
    }
}
