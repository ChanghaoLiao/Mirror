import AppKit
import CoreMedia
import MirrorCore
import ScreenCaptureKit

final class FrameTrace: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var active = false
    private var timestamps: [Double] = []
    func enable() {
        lock.lock()
        active = true
        lock.unlock()
    }
    func snapshot() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return timestamps
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType)
    {
        guard type == .screen, buffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue
        else { return }
        lock.lock()
        defer { lock.unlock() }
        if active { timestamps.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))) }
    }
}
@MainActor final class AnimationFrames: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                MirrorPreferences.blackboard = true
                var panels: [NSWindow] = []
                var readers: [ConversationReader] = []
                let conversation = Conversation(
                    summary: .init(id: "synthetic", title: "Synthetic"),
                    messages: (0..<30).map {
                        Message(
                            id: "m\($0)", role: "assistant", text: "中文 **阅读** English `code`。\n\n连续字号更新与开场动画。"
                        )
                    })
                let visible = NSScreen.main!.visibleFrame
                for i in 0..<4 {
                    let panel = NSWindow(
                        contentRect: NSRect(
                            x: visible.minX + 30 + CGFloat(i) * 50, y: visible.minY + 30 + CGFloat(i) * 20,
                            width: 900, height: 490), styleMask: [.titled], backing: .buffered, defer: false)
                    panel.isReleasedWhenClosed = false
                    let view = OceanView(frame: panel.contentView!.bounds)
                    view.showsBlackboard = true
                    let reader = ConversationReader(frame: view.bounds.insetBy(dx: 30, dy: 40))
                    reader.show(conversation, settings: ReadingSettings(), anchor: nil)
                    view.addSubview(reader)
                    panel.contentView = view
                    panel.orderFront(nil)
                    panel.displayIfNeeded()
                    panels.append(panel)
                    readers.append(reader)
                }
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(nanoseconds: 150_000_000)
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: false)
                var traces: [FrameTrace] = []
                var streams: [SCStream] = []
                for panel in panels {
                    guard
                        let window = content.windows.first(where: {
                            $0.windowID == UInt32(panel.windowNumber)
                        })
                    else { throw NSError(domain: "missing-window", code: 1) }
                    let config = SCStreamConfiguration()
                    config.width = 900
                    config.height = 520
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                    config.showsCursor = false
                    config.capturesAudio = false
                    config.queueDepth = 5
                    let trace = FrameTrace()
                    let stream = SCStream(
                        filter: SCContentFilter(desktopIndependentWindow: window), configuration: config,
                        delegate: nil)
                    try stream.addStreamOutput(
                        trace, type: .screen,
                        sampleHandlerQueue: DispatchQueue(label: "frames.\(panel.windowNumber)"))
                    try await stream.startCapture()
                    traces.append(trace)
                    streams.append(stream)
                }
                for trace in traces { trace.enable() }
                for panel in panels { BlackboardOpening.show(in: panel.contentView!) }
                for frame in 0..<66 {
                    try? await Task.sleep(nanoseconds: 16_666_667)
                    if frame % 8 == 0 {
                        for reader in readers { reader.updateFontSize(frame % 16 == 0 ? 22 : 23) }
                    }
                }
                for stream in streams { try await stream.stopCapture() }
                for (i, trace) in traces.enumerated() {
                    let stamps = trace.snapshot()
                    let intervals = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }.sorted()
                    let p95 =
                        intervals.isEmpty
                        ? 999 : intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
                    let maxGap = intervals.last ?? 999
                    print(
                        "SCREEN_FRAME window=\(i) complete_frames=\(stamps.count) p95_ms=\(p95) max_gap_ms=\(maxGap)"
                    )
                    guard stamps.count >= 50, maxGap <= 50 else {
                        throw NSError(domain: "frame-budget", code: i)
                    }
                }
                for panel in panels { panel.close() }
                print("SCREEN_FRAME_PASS filtered-synthetic-windows-only no-images-or-audio-saved")
                NSApp.terminate(nil)
            } catch {
                print("SCREEN_FRAME_FAIL \(error)")
                exit(1)
            }
        }
    }
}
@main struct Main {
    static func main() {
        let app = NSApplication.shared
        let probe = AnimationFrames()
        app.setActivationPolicy(.accessory)
        app.delegate = probe
        app.run()
    }
}
