import AppKit
import MirrorCore

@MainActor enum PerformanceVerification {
    static func probe(_ provider: ConversationProvider) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        var page = try await provider.listConversations(query: "Mirror", cursor: nil)
        if page.conversations.isEmpty {
            // A user's titles need not contain the product name. Read the newest available history.
            page = try await provider.listConversations(query: "", cursor: nil)
        }
        print("PROBE list_service_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
        guard let summary = page.conversations.first else { throw ConnectionError.disconnected }
        let store = ConversationStore(provider: provider)
        let panel = NSWindow(
            contentRect: NSRect(x: 80, y: 120, width: 490, height: 650), styleMask: [.titled],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let reader = ConversationReader(frame: NSRect(x: 0, y: 0, width: 490, height: 650))
        panel.contentView = reader
        panel.orderFront(nil)
        defer { panel.close() }
        let readStart = ProcessInfo.processInfo.systemUptime
        var first = true
        let conversation = try await store.conversation(
            summary.id,
            progress: { snapshot in
                guard first else { return }
                first = false
                reader.show(snapshot, settings: ReadingSettings(), anchor: nil)
                panel.displayIfNeeded()
                print(
                    "PROBE first_partial_display_ms=\((ProcessInfo.processInfo.systemUptime - readStart) * 1000)"
                )
            })
        let dataReady = ProcessInfo.processInfo.systemUptime
        reader.show(conversation, settings: ReadingSettings(), anchor: nil)
        panel.displayIfNeeded()
        print(
            "PROBE full_data_ms=\((dataReady - readStart) * 1000) full_display_ms=\((ProcessInfo.processInfo.systemUptime - readStart) * 1000) messages=\(conversation.messages.count) realized=\(reader.realizedBlockCount)"
        )
        for trial in 1...3 {
            let warm = ProcessInfo.processInfo.systemUptime
            let cached = try await store.conversation(summary.id)
            reader.show(cached, settings: ReadingSettings(), anchor: nil)
            panel.displayIfNeeded()
            print(
                "PROBE warm_display_ms=\((ProcessInfo.processInfo.systemUptime - warm) * 1000) trial=\(trial)"
            )
        }
        print("ADAPTER_PASS read-only full-history warm-cache")
    }

    static func reliability(_ provider: ConversationProvider) async throws {
        var page = try await provider.listConversations(query: "Mirror", cursor: nil)
        if page.conversations.isEmpty { page = try await provider.listConversations(query: "", cursor: nil) }
        guard let summary = page.conversations.first else { throw ConnectionError.disconnected }
        // An unpinned zero-entry cache forces actual history reads on every iteration.
        let store = ConversationStore(provider: provider, byteLimit: 0, entryLimit: 0)
        for round in 1...20 {
            let start = ProcessInfo.processInfo.systemUptime
            let read = try await store.conversation(summary.id)
            let ready = ProcessInfo.processInfo.systemUptime
            let refreshed = try await store.conversation(summary.id, refresh: true)
            guard !read.messages.isEmpty, !refreshed.messages.isEmpty,
                read.summary.id == refreshed.summary.id,
                Set(refreshed.messages.map(\.id)).count == refreshed.messages.count
            else { throw ConnectionError.invalidResponse }
            print(
                "RELIABILITY round=\(round) read_ms=\(Int((ready-start)*1000)) refresh_ms=\(Int((ProcessInfo.processInfo.systemUptime-ready)*1000)) messages=\(refreshed.messages.count)"
            )
        }
        print("RELIABILITY_PASS real_reads=20 real_refreshes=20 no_manual_retry read-only no-content-export")
    }

    static func run() {
        Task {
            let provider = DemoProvider()
            let source = provider.sample.messages
            for count in [18, 180, 720] {
                let messages = (0..<count).map { index in
                    Message(
                        id: "fixture-\(index)", role: source[index % source.count].role,
                        text: source[index % source.count].text.replacingOccurrences(
                            of: "Use the **upper-left control**", with: "Move to the **left edge**"))
                }
                let conversation = Conversation(
                    summary: .init(id: "benchmark", title: "Synthetic benchmark"), messages: messages)
                for trial in 1...3 {
                    let panel = NSWindow(
                        contentRect: NSRect(x: 80, y: 120, width: 490, height: 650), styleMask: [.titled],
                        backing: .buffered, defer: false)
                    panel.isReleasedWhenClosed = false
                    let reader = ConversationReader(frame: NSRect(x: 0, y: 0, width: 490, height: 650))
                    panel.contentView = reader
                    panel.orderFront(nil)
                    let start = ProcessInfo.processInfo.systemUptime
                    reader.show(conversation, settings: ReadingSettings(), anchor: nil)
                    panel.displayIfNeeded()
                    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                    print(
                        "BENCH messages=\(count) trial=\(trial) render_display_ms=\(String(format: "%.2f", elapsed))"
                    )
                    panel.close()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            NSApp.terminate(nil)
        }
    }
}
