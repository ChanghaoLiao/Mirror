import AppKit
import CoreText
import QuartzCore

/// Decorative material only. Conversation text, hit targets and scrolling remain native.
enum BlackboardMaterial {
    private static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Mirror_Mirror.bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        return .module
    }()
    static let image = resources.url(
        forResource: "blackboard", withExtension: "png", subdirectory: "Resources"
    )
    .flatMap { NSImage(contentsOf: $0) }
    private static let registered: Bool = {
        guard
            let url = resources.url(
                forResource: "MaShanZheng-Regular", withExtension: "ttf", subdirectory: "Resources")
        else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        guard MirrorPreferences.blackboard else { return .systemFont(ofSize: size, weight: weight) }
        _ = registered
        return NSFont(name: "MaShanZheng-Regular", size: size) ?? NSFont(name: "Kaiti SC", size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
    static func draw(in rect: NSRect) {
        image?.draw(
            in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high])
    }
}

/// Decorative, cancellable reveal; never consumes the triggering input.
final class BlackboardOpening: NSView, CAAnimationDelegate {
    static let duration: TimeInterval = 1.2
    static let pulses = 5
    private var monitor: Any?
    private var closing: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    private var started: TimeInterval = 0
    private var active = false
    private var renderedSize = NSSize.zero
    private(set) var compositorLayer: CALayer?
    var progress: CGFloat { min(1, max(0, CGFloat((CACurrentMediaTime() - started) / Self.duration))) }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    static func show(in view: NSView) {
        let opening = BlackboardOpening(frame: view.bounds)
        opening.autoresizingMask = [.width, .height]
        view.addSubview(opening)
        opening.start()
    }
    func start() {
        guard MirrorPreferences.blackboard, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            skip()
            return
        }
        started = CACurrentMediaTime()
        active = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown,
        ]) { [weak self] event in
            if let self, event.window === self.window { self.skip() }
            return event
        }
        closing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in self?.skip() }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self?.skip() }
        }
        buildLayers(from: 0)
    }
    private func cleanup() {
        active = false
        compositorLayer?.removeAllAnimations()
        for child in layer?.sublayers ?? [] { child.removeFromSuperlayer() }
        compositorLayer = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let closing {
            NotificationCenter.default.removeObserver(closing)
            self.closing = nil
        }
        if let motionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(motionObserver)
            self.motionObserver = nil
        }
    }
    func skip() {
        cleanup()
        removeFromSuperview()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cleanup() }
        super.viewWillMove(toWindow: newWindow)
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let closing { NotificationCenter.default.removeObserver(closing) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag && active { skip() }
    }
    override func layout() {
        super.layout()
        if active && renderedSize != bounds.size { buildLayers(from: progress) }
    }
    /// Static shapes are uploaded once; only their positions/opacity animate in the compositor.
    private func buildLayers(from initial: CGFloat) {
        guard initial < 1, let root = layer else {
            skip()
            return
        }
        let board = bounds.insetBy(dx: 22, dy: 30)
        guard board.width > 0, board.height > 0 else {
            skip()
            return
        }
        renderedSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for child in root.sublayers ?? [] { child.removeFromSuperlayer() }
        let canvas = CALayer()
        canvas.frame = board
        canvas.masksToBounds = true
        root.addSublayer(canvas)
        let white = NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 1).cgColor
        let nx = 1 / board.width
        let ny = 1 / board.height
        let norm = hypot(nx, ny)
        let normal = CGPoint(x: nx / norm, y: ny / norm)
        let tangent = CGPoint(x: -normal.y, y: normal.x)
        let extent = hypot(board.width, board.height) * 3
        let wipe = CALayer()
        wipe.anchorPoint = .zero
        canvas.addSublayer(wipe)
        compositorLayer = wipe
        let shape = CAShapeLayer()
        let path = CGMutablePath()
        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: normal.x * along + tangent.x * across, y: normal.y * along + tangent.y * across)
        }
        path.move(to: point(16, -extent))
        path.addLine(to: point(extent, -extent))
        path.addLine(to: point(extent, extent))
        path.addLine(to: point(16, extent))
        path.closeSubpath()
        shape.path = path
        shape.fillColor = white
        wipe.addSublayer(shape)
        let edge = CAGradientLayer()
        edge.bounds = CGRect(x: 0, y: 0, width: 16, height: extent * 2)
        edge.position = point(8, 0)
        edge.startPoint = CGPoint(x: 0, y: 0.5)
        edge.endPoint = CGPoint(x: 1, y: 0.5)
        edge.colors = [NSColor.clear.cgColor, white]
        edge.transform = CATransform3DMakeRotation(atan2(normal.y, normal.x), 0, 0, 1)
        wipe.addSublayer(edge)
        let eraser = CALayer()
        eraser.bounds = CGRect(x: -46, y: -23, width: 92, height: 46)
        eraser.backgroundColor = NSColor(srgbRed: 0.32, green: 0.24, blue: 0.17, alpha: 1).cgColor
        eraser.cornerRadius = 6
        eraser.borderWidth = 2
        eraser.borderColor = NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 0.7).cgColor
        eraser.shadowColor = NSColor.black.cgColor
        eraser.shadowOpacity = 0.35
        eraser.shadowOffset = CGSize(width: 0, height: 3)
        eraser.shadowRadius = 5
        eraser.shadowPath = CGPath(
            roundedRect: eraser.bounds, cornerWidth: 6, cornerHeight: 6, transform: nil)
        let felt = CALayer()
        felt.frame = CGRect(x: -45, y: 8, width: 90, height: 14)
        felt.backgroundColor = NSColor(srgbRed: 0.14, green: 0.14, blue: 0.13, alpha: 1).cgColor
        felt.cornerRadius = 3
        eraser.addSublayer(felt)
        canvas.addSublayer(eraser)
        let dust = CALayer()
        canvas.addSublayer(dust)
        for i in 0..<9 {
            let dot = CALayer()
            let distance = CGFloat(i) * 6 + 12
            let phase = CGFloat(i) * 2.4
            let size = CGFloat(2 + i % 3)
            dot.frame = CGRect(
                x: -distance + sin(phase) * 9, y: -distance * board.height / board.width + cos(phase) * 12,
                width: size, height: size)
            dot.cornerRadius = size / 2
            dot.backgroundColor = white
            dot.opacity = 0.22
            dust.addSublayer(dot)
        }
        let times = (0...120).map { Double($0) / 120 }
        let progress = times.map { initial + (1 - initial) * CGFloat($0) }
        let positions = progress.map { p -> CGPoint in
            let m = Self.motion(at: p)
            return CGPoint(x: board.width * m.x, y: board.height * m.y)
        }
        func animate(_ target: CALayer, key: String, values: [Any], complete: Bool = false) {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times.map { NSNumber(value: $0) }
            animation.duration = Self.duration * Double(1 - initial)
            animation.calculationMode = .linear
            if complete { animation.delegate = self }
            target.setValue(values.last, forKeyPath: key)
            target.add(animation, forKey: key)
        }
        let wipePositions = zip(positions, progress).map { p, t in
            NSValue(point: CGPoint(x: p.x - normal.x * 16 * (1 - t), y: p.y - normal.y * 16 * (1 - t)))
        }
        animate(wipe, key: "position", values: wipePositions, complete: true)
        animate(eraser, key: "position", values: positions.map { NSValue(point: $0) })
        animate(dust, key: "position", values: positions.map { NSValue(point: $0) })
        animate(
            eraser, key: "transform.rotation.z",
            values: progress.map {
                NSNumber(value: Double(-atan2(board.height, board.width) + sin($0 * 10 * .pi) * 0.035))
            })
        let opacity = progress.map { NSNumber(value: Double(min(1, $0 * 20) * min(1, (1 - $0) * 20))) }
        animate(eraser, key: "opacity", values: opacity)
        animate(dust, key: "opacity", values: opacity)
        CATransaction.commit()
    }
    struct Motion {
        let x: CGFloat
        let y: CGFloat
    }
    /// One diagonal pass, with five rhythmic speed surges and soft start/end.
    static func motion(at progress: CGFloat) -> Motion {
        let t = min(1, max(0, progress))
        let frequency = 2 * CGFloat.pi * CGFloat(pulses)
        let rhythmic = t - 0.65 * sin(frequency * t) / frequency
        let distance = rhythmic * rhythmic * (3 - 2 * rhythmic)
        return Motion(x: distance, y: distance)
    }
    /// White side of a diagonal front: x + y >= 2 * distance.
    static func remaining(at progress: CGFloat) -> [CGPoint] {
        guard progress < 1 else { return [] }
        let edge = 2 * motion(at: progress).x
        if edge <= 0 {
            return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        }
        if edge < 1 {
            return [
                CGPoint(x: edge, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
                CGPoint(x: 0, y: edge),
            ]
        }
        return [CGPoint(x: 1, y: edge - 1), CGPoint(x: 1, y: 1), CGPoint(x: edge - 1, y: 1)]
    }
}
