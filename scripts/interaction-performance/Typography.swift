import AppKit
import MirrorCore

@MainActor final class Probe: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            MirrorPreferences.blackboard = true
            for count in [18, 720] {
                let text = String(
                    repeating:
                        "黑板阅读需要保留同一个汉字的位置，**字体加减**不能重新解析历史。English `code` [link](https://example.com)。\n\n",
                    count: 4)
                let conversation = Conversation(
                    summary: .init(id: "probe", title: "Synthetic"),
                    messages: (0..<count).map { Message(id: "m\($0)", role: "assistant", text: text) })
                let panel = NSWindow(
                    contentRect: NSRect(x: 40, y: 80, width: 1120, height: 590), styleMask: [.titled],
                    backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                let reader = ConversationReader(frame: panel.contentView!.bounds)
                panel.contentView = reader
                panel.orderFront(nil)
                var settings = ReadingSettings()
                reader.show(conversation, settings: settings, anchor: nil)
                panel.displayIfNeeded()
                var samples: [Double] = []
                for i in 0..<40 {
                    settings.fontSize = i % 2 == 0 ? 22 : 23
                    let start = ProcessInfo.processInfo.systemUptime
                    #if OPTIMIZED
                        reader.updateFontSize(settings.fontSize)
                    #else
                        reader.show(conversation, settings: settings, anchor: reader.anchor)
                    #endif
                    panel.displayIfNeeded()
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                samples.sort()
                print(
                    "FONT messages=\(count) p95_ms=\(samples[37]) max_ms=\(samples.last!) realized=\(reader.realizedBlockCount)"
                )
                #if OPTIMIZED
                    if samples[37] > 50 {
                        print("FONT_FAIL p95 exceeds 50ms")
                        exit(1)
                    }
                #endif
                panel.close()
            }
            NSApp.terminate(nil)
        }
    }
}
@main struct Main {
    static func main() {
        let app = NSApplication.shared
        let probe = Probe()
        app.setActivationPolicy(.accessory)
        app.delegate = probe
        app.run()
    }
}
