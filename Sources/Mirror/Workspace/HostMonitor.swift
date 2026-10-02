import AppKit
import ApplicationServices
import MirrorCore

struct HostWindow {
    let element: AXUIElement
    let pid: pid_t
    var title: String
    let bundleID: String
}

@MainActor final class HostMonitor {
    static let bundles = ["com.openai.codex"]
    private var observers: [pid_t: AXObserver] = [:]
    private var notifications: [NSObjectProtocol] = []
    var bindings: [UUID: HostWindow] = [:]
    var lastHost: HostWindow?
    var onChange: (() -> Void)?
    var trusted: Bool { AXIsProcessTrusted() }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            notifications.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                })
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            notifications.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    DispatchQueue.main.async { self?.refresh() }
                })
        }
        refresh()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func refresh() {
        for (pid, observer) in observers where NSRunningApplication(processIdentifier: pid) == nil {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = nil
        }
        guard trusted else {
            lastHost = nil
            for observer in observers.values {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            observers.removeAll()
            onChange?()
            return
        }
        for (id, host) in bindings where exists(host) {
            var updated = host
            updated.title = string(host.element, kAXTitleAttribute)
            bindings[id] = updated
        }
        if let lastHost, !exists(lastHost) { self.lastHost = nil }
        for app in NSWorkspace.shared.runningApplications
        where Self.bundles.contains(app.bundleIdentifier ?? "") {
            watch(app)
        }
        if let app = NSWorkspace.shared.frontmostApplication,
            Self.bundles.contains(app.bundleIdentifier ?? ""),
            let focused = focusedWindow(pid: app.processIdentifier)
        {
            lastHost = HostWindow(
                element: focused, pid: app.processIdentifier,
                title: string(focused, kAXTitleAttribute), bundleID: app.bundleIdentifier ?? "")
        }
        onChange?()
    }

    func currentContext(referenceWorkspace: UUID?) -> ActiveContext {
        // AppKit activation can precede NSWorkspace's frontmost-process notification.
        if NSApp.isActive { return referenceWorkspace.map(ActiveContext.reference) ?? .unrelated }
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unrelated }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return referenceWorkspace.map(ActiveContext.reference) ?? .unrelated
        }
        guard Self.bundles.contains(app.bundleIdentifier ?? ""),
            let focused = focusedWindow(pid: app.processIdentifier)
        else { return .unrelated }
        return bindings.first(where: { CFEqual($0.value.element, focused) }).map { .host($0.key) }
            ?? .unrelated
    }

    func availability(_ id: UUID) -> HostAvailability {
        guard trusted else { return .unavailable }
        guard let host = bindings[id] else { return .restoring }
        guard let app = NSRunningApplication(processIdentifier: host.pid) else { return .closed }
        guard
            let windows = value(AXUIElementCreateApplication(host.pid), kAXWindowsAttribute) as? [AXUIElement]
        else { return .unavailable }
        guard windows.contains(where: { CFEqual($0, host.element) }) else { return .closed }
        if app.isHidden { return .hidden }
        guard let minimized = value(host.element, kAXMinimizedAttribute) as? Bool else { return .unavailable }
        return minimized ? .minimized : .available
    }
    func available(_ id: UUID) -> Bool { availability(id) == .available }

    private func exists(_ host: HostWindow) -> Bool {
        guard NSRunningApplication(processIdentifier: host.pid) != nil,
            let windows = value(AXUIElementCreateApplication(host.pid), kAXWindowsAttribute) as? [AXUIElement]
        else { return false }
        return windows.contains { CFEqual($0, host.element) }
    }

    func rebind(_ workspace: WorkspaceState) {
        guard trusted, bindings[workspace.id] == nil else { return }
        var matches: [HostWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == workspace.hostBundleID
        {
            let windows =
                value(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute)
                as? [AXUIElement] ?? []
            for window in windows where string(window, kAXTitleAttribute) == workspace.hostTitle {
                matches.append(
                    HostWindow(
                        element: window, pid: app.processIdentifier,
                        title: workspace.hostTitle, bundleID: workspace.hostBundleID))
            }
        }
        if matches.count == 1 { bindings[workspace.id] = matches[0] }
    }

    func selectedText(_ host: HostWindow) -> String? {
        guard let focus = element(AXUIElementCreateApplication(host.pid), kAXFocusedUIElementAttribute)
        else { return nil }
        return value(focus, kAXSelectedTextAttribute) as? String
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard trusted, observers[pid] == nil else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(
            pid,
            { _, _, _, context in
                guard let context else { return }
                let monitor = Unmanaged<HostMonitor>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in monitor.refresh() }
            }, &observer)
        guard result == .success, let observer else { return }
        observers[pid] = observer
        let context = Unmanaged.passUnretained(self).toOpaque()
        let application = AXUIElementCreateApplication(pid)
        for name in [
            kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
            kAXApplicationHiddenNotification, kAXApplicationShownNotification,
        ] {
            AXObserverAddNotification(observer, application, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        // Register per-window events; newly created windows are enrolled on the next refresh.
        enrollWindows(pid, observer: observer)
    }

    private func enrollWindows(_ pid: pid_t, observer: AXObserver) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        for window in value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            for name in [
                kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
            ] {
                AXObserverAddNotification(observer, window, name as CFString, context)
            }
        }
    }

    func focusedWindow(pid: pid_t) -> AXUIElement? {
        if let observer = observers[pid] { enrollWindows(pid, observer: observer) }
        return element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
    }
    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else {
            return nil
        }
        return result
    }
    private func element(_ source: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = value(source, name), CFGetTypeID(result) == AXUIElementGetTypeID() else {
            return nil
        }
        return (result as! AXUIElement)
    }
    private func string(_ element: AXUIElement, _ name: String) -> String {
        value(element, name) as? String ?? ""
    }
}
