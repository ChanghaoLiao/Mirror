import AppKit
import MirrorCore
import UniformTypeIdentifiers

final class ReadingTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func scrollWheel(with event: NSEvent) {
        // Vertical gestures always belong to the conversation; code keeps horizontal scrolling.
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
            let outer = enclosingScrollView?.enclosingScrollView
        {
            outer.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

final class ReadingBlock: NSView {
    let messageID: String
    let index: Int
    let textView: ReadingTextView?
    private let horizontal: NSScrollView?
    private var imageView: NSImageView?
    private var imageButton: NSButton?
    var previewImage: NSImage? { imageView?.image }
    var onGeometryChange: (() -> Void)?
    private let intrinsicWidth: CGFloat
    override var isFlipped: Bool { true }

    init(messageID: String, index: Int, block: MarkdownBlock, fontSize: CGFloat) {
        self.messageID = messageID
        self.index = index
        var quoted = false
        var literal = false
        var scrolling = false
        var size = fontSize
        var text = ""
        var weight = NSFont.Weight.regular
        var color = index == -1 ? Ocean.accentText : Ocean.text
        let localImage: NSImage? = nil
        var isImage = false
        switch block {
        case .paragraph(let value), .list(let value): text = value
        case .heading(let value, let level):
            text = value
            size += level == 1 ? 7 : level == 2 ? 1 : 0
            weight = .semibold
        case .quote(let value):
            quoted = true
            text = "│  " + value
            color = Ocean.secondary
        case .code(let value, _):
            text = value
            literal = true
            scrolling = true
            size -= 1
        case .table(let rows):
            let count = rows.map(\.count).max() ?? 0
            let widths = (0..<count).map { col in rows.map { col < $0.count ? $0[col].count : 0 }.max() ?? 0 }
            text = rows.map { row in
                (0..<count).map { col in
                    let cell = col < row.count ? row[col] : ""
                    return cell + String(repeating: " ", count: max(0, widths[col] - cell.count))
                }.joined(separator: "   │   ")
            }.joined(separator: "\n")
            literal = true
            scrolling = true
            size -= 1
        case .image(let alt, let path):
            isImage = true
            text = localImage == nil ? "\(alt.isEmpty ? "Image" : alt) — image not loaded\n\(path)" : ""
            color = Ocean.secondary
        case .divider:
            text = "────────────────"
            color = Ocean.divider
        }
        if let localImage {
            imageView = NSImageView(image: localImage)
            textView = nil
            horizontal = nil
            intrinsicWidth = 0
        } else {
            let view = ReadingTextView(frame: .zero)
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.linkTextAttributes = [
                .foregroundColor: Ocean.accentText, .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            view.selectedTextAttributes = [.backgroundColor: Ocean.selection, .foregroundColor: Ocean.text]
            view.textContainerInset = NSSize(width: quoted ? 16 : 0, height: quoted ? 12 : 3)
            if quoted {
                view.drawsBackground = true
                view.backgroundColor = Ocean.subtle
            }
            view.textContainer?.lineFragmentPadding = scrolling ? 10 : 0
            view.isVerticallyResizable = true
            let font =
                literal
                ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
            let attributed = Self.attributed(text, font: font, color: color, literal: literal)
            view.textStorage?.setAttributedString(attributed)
            view.setAccessibilityLabel(text)
            textView = view
            imageView = nil
            intrinsicWidth = scrolling ? ceil(attributed.size().width) + 24 : 0
            if scrolling {
                let scroll = NSScrollView()
                scroll.drawsBackground = true
                scroll.backgroundColor = Ocean.subtle
                scroll.hasHorizontalScroller = true
                scroll.hasVerticalScroller = false
                scroll.autohidesScrollers = true
                scroll.documentView = view
                view.isHorizontallyResizable = true
                view.textContainer?.widthTracksTextView = false
                horizontal = scroll
            } else {
                horizontal = nil
            }
        }
        super.init(frame: .zero)
        if isImage {
            let button = NSButton(
                title: localized("Choose image to preview…", "选择图片以预览…"), target: self,
                action: #selector(chooseImage)
            )
            button.bezelStyle = .rounded
            imageButton = button
            addSubview(button)
        }
        if let imageView { addSubview(imageView) }
        if let horizontal { addSubview(horizontal) } else if let textView { addSubview(textView) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func chooseImage() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message =
            localized(
                "Choose the image you want to display. Mirror does not read attachment paths automatically.",
                "选择要预览的图片。Mirror 不会自动读取附件路径。")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url), let self else {
                return
            }
            self.installImage(image)
            self.onGeometryChange?()
        }
    }

    func installImage(_ image: NSImage) {
        imageView?.removeFromSuperview()
        let preview = NSImageView(image: image)
        preview.setAccessibilityLabel(localized("Selected image preview", "所选图片预览"))
        imageView = preview
        addSubview(preview)
        textView?.isHidden = true
        imageButton?.isHidden = true
    }

    static func searchableText(_ block: MarkdownBlock) -> String {
        var text: String
        var literal = false
        switch block {
        case .paragraph(let value), .list(let value), .heading(let value, _): text = value
        case .quote(let value): text = "│  " + value
        case .code(let value, _):
            text = value
            literal = true
        case .table(let rows):
            let count = rows.map(\.count).max() ?? 0
            let widths = (0..<count).map { col in rows.map { col < $0.count ? $0[col].count : 0 }.max() ?? 0 }
            text = rows.map { row in
                (0..<count).map { col in
                    let cell = col < row.count ? row[col] : ""
                    return cell + String(repeating: " ", count: max(0, widths[col] - cell.count))
                }.joined(separator: "   │   ")
            }.joined(separator: "\n")
            literal = true
        case .image(let alt, let path):
            text = "\(alt.isEmpty ? "Image" : alt) — image not loaded\n\(path)"
            literal = true
        case .divider: return "────────────────"
        }
        if !literal,
            let markdown = try? AttributedString(
                markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        {
            return String(markdown.characters)
        }
        return text
    }

    func arrange(width: CGFloat) -> CGFloat {
        if let imageView, let image = imageView.image {
            let height = min(500, width * image.size.height / max(1, image.size.width))
            imageView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            return height + 10
        }
        guard let textView, let container = textView.textContainer, let manager = textView.layoutManager
        else { return 1 }
        let contentWidth = max(width, intrinsicWidth)
        container.containerSize = NSSize(
            width: contentWidth - textView.textContainerInset.width * 2, height: .greatestFiniteMagnitude)
        textView.frame.size.width = contentWidth
        manager.ensureLayout(for: container)
        let height = max(
            24, ceil(manager.usedRect(for: container).height) + max(8, textView.textContainerInset.height * 2)
        )
        textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        horizontal?.frame = NSRect(x: 0, y: 0, width: width, height: height + 12)
        imageButton?.frame = NSRect(x: 0, y: height + 4, width: min(width, 230), height: 28)
        return height + (horizontal == nil ? 8 : 20) + (imageButton == nil ? 0 : 36)
    }

    func character(at y: CGFloat) -> Int {
        guard let textView, let container = textView.textContainer, let manager = textView.layoutManager,
            manager.numberOfGlyphs > 0
        else { return 0 }
        let glyph = manager.glyphIndex(
            for: NSPoint(x: 1, y: max(0, y - textView.textContainerInset.height)), in: container)
        return manager.characterIndexForGlyph(at: min(glyph, manager.numberOfGlyphs - 1))
    }
    func y(character: Int) -> CGFloat {
        guard let textView, let manager = textView.layoutManager, manager.numberOfGlyphs > 0 else { return 0 }
        let length = (textView.string as NSString).length
        let glyph = manager.glyphIndexForCharacter(at: min(max(0, character), max(0, length - 1)))
        return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            + textView.textContainerInset.height
    }

    private static func attributed(_ text: String, font: NSFont, color: NSColor, literal: Bool)
        -> NSAttributedString
    {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        var result = NSMutableAttributedString(string: text)
        if !literal,
            let markdown = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        {
            result = NSMutableAttributedString(attributedString: NSAttributedString(markdown))
        }
        let range = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.link, in: range) { value, linkRange, _ in
            guard let value else { return }
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            if !["https", "http", "mailto"].contains(url?.scheme?.lowercased() ?? "") {
                result.removeAttribute(.link, range: linkRange)
            }
        }
        result.addAttributes(
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], range: range)
        if !literal {
            result.enumerateAttribute(.inlinePresentationIntent, in: range) { value, range, _ in
                guard let intent = value as? InlinePresentationIntent else { return }
                var styled = font
                if intent.contains(.stronglyEmphasized) {
                    styled = NSFontManager.shared.convert(styled, toHaveTrait: .boldFontMask)
                }
                if intent.contains(.emphasized) {
                    styled = NSFontManager.shared.convert(styled, toHaveTrait: .italicFontMask)
                }
                if intent.contains(.code) {
                    styled = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                }
                result.addAttribute(.font, value: styled, range: range)
                if intent.contains(.strikethrough) {
                    result.addAttribute(.strikethroughStyle, value: 1, range: range)
                }
            }
        }
        return result
    }
}
