import AppKit

extension Notification.Name {
    static let mirrorPreferencesChanged = Notification.Name("Mirror.preferencesChanged")
    static let mirrorShowPreferences = Notification.Name("Mirror.showPreferences")
    static let mirrorShowSetup = Notification.Name("Mirror.showSetup")
}

enum MirrorPreferences {
    static let defaults: UserDefaults =
        ProcessInfo.processInfo.environment["MIRROR_PREFS_SUITE"]
        .flatMap(UserDefaults.init(suiteName:)) ?? .standard
    static var language: String {
        get {
            defaults.string(forKey: "mirror.ui.language")
                ?? (Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en")
        }
        set {
            defaults.set(newValue, forKey: "mirror.ui.language")
            changed()
        }
    }
    static var appearance: String {
        get { defaults.string(forKey: "mirror.ui.appearance") ?? "system" }
        set {
            defaults.set(newValue, forKey: "mirror.ui.appearance")
            changed()
        }
    }
    static func applyAppearance() {
        NSApp.appearance =
            appearance == "dark"
            ? NSAppearance(named: .darkAqua)
            : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    private static func changed() {
        applyAppearance()
        NotificationCenter.default.post(name: .mirrorPreferencesChanged, object: nil)
    }
}

func localized(_ english: String, _ chinese: String) -> String {
    MirrorPreferences.language == "zh" ? chinese : english
}

enum Ocean {
    private static func color(_ name: String, _ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("Mirror." + name)) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let canvas = color("canvas", 0xF7FAFB, 0x0E1417)
    static let surface = color("surface", 0xFFFFFF, 0x151D21)
    static let subtle = color("subtle", 0xEFF5F7, 0x1B272C)
    static let text = color("text", 0x182024, 0xF2F7F9)
    static let secondary = color("secondary", 0x59676E, 0xAAB8BE)
    static let border = color("border", 0xDCE8EC, 0x26363D)
    static let divider = color("divider", 0xE6EEF1, 0x202D33)
    static let accent = color("accent", 0x0EA5E9, 0x38BDF8)
    static let accentText = color("accentText", 0x036B9D, 0x82D8FC)
    static let accentSoft = color("accentSoft", 0xE8F7FE, 0x132833)
    static let onAccent = color("onAccent", 0x06202E, 0x071A22)
    static let selection = color("selection", 0xD8F2FD, 0x18394A)
    static let danger = color("danger", 0xB42318, 0xFF8A80)
}

class OceanView: NSView {
    var fill: NSColor = Ocean.surface { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
    }
}

final class OceanButton: NSButton {
    enum Kind { case quiet, primary, selected }
    var textAlignment: NSTextAlignment = .center
    var kind: Kind = .quiet { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        font = .systemFont(ofSize: 13)
        focusRingType = .exterior
        setButtonType(.momentaryPushIn)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor =
            kind == .primary
            ? Ocean.accent
            : kind == .selected ? Ocean.accentSoft : hovered || isHighlighted ? Ocean.subtle : .clear
        if kind != .quiet || hovered || isHighlighted {
            background.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        let style = NSMutableParagraphStyle()
        style.alignment = textAlignment
        style.lineBreakMode = .byTruncatingTail
        let color = kind == .primary ? Ocean.onAccent : kind == .selected ? Ocean.accentText : Ocean.text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: color.withAlphaComponent(isEnabled ? 1 : 0.4), .paragraphStyle: style,
        ]
        var label = title
        var shortcut: String?
        if textAlignment == .left, let range = title.range(of: "  ⌘") {
            label = String(title[..<range.lowerBound])
            shortcut = String(title[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }
        let height = (label as NSString).size(withAttributes: attributes).height
        (label as NSString).draw(
            in: NSRect(
                x: textAlignment == .left ? 12 : 6, y: (bounds.height - height) / 2,
                width: max(0, bounds.width - (textAlignment == .center ? 12 : shortcut == nil ? 24 : 72)),
                height: height + 2),
            withAttributes: attributes)
        if let shortcut {
            let right = NSMutableParagraphStyle()
            right.alignment = .right
            (shortcut as NSString).draw(
                in: NSRect(
                    x: bounds.width - 54, y: (bounds.height - height) / 2, width: 42, height: height + 2),
                withAttributes: [
                    .font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: Ocean.secondary,
                    .paragraphStyle: right,
                ])
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

func oceanButton(_ title: String, target: AnyObject?, action: Selector?, primary: Bool = false) -> OceanButton
{
    let button = OceanButton(frame: .zero)
    button.title = title
    button.target = target
    button.action = action
    button.kind = primary ? .primary : .quiet
    return button
}

func oceanDivider(in view: NSView, y: CGFloat, width: CGFloat) {
    let divider = OceanView(frame: NSRect(x: 32, y: y, width: width, height: 1))
    divider.fill = Ocean.divider
    view.addSubview(divider)
}
