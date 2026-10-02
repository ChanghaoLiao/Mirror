import AppKit
import MirrorCore

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Lightweight geometry for the whole history; native text layouts exist only near the viewport.
final class ConversationReader: NSScrollView {
    private struct Slot {
        let messageID: String
        let index: Int
        let block: MarkdownBlock
        let fontSize: CGFloat
        var frame = NSRect.zero
        var height: CGFloat = 80
        var measuredWidth: CGFloat = 0
        var view: ReadingBlock?
        var selectedImage: NSImage?
    }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        let top = contentView.bounds.minY
        let page = contentSize.height * 0.9
        let bottom = max(0, document.frame.height - contentSize.height)
        let destination: CGFloat
        switch event.keyCode {
        case 125: destination = top + 40
        case 126: destination = top - 40
        case 121: destination = top + page
        case 116: destination = top - page
        case 115: destination = 0
        case 119: destination = bottom
        default:
            super.keyDown(with: event)
            return
        }
        contentView.scroll(to: NSPoint(x: 0, y: min(bottom, max(0, destination))))
        reflectScrolledClipView(contentView)
    }
    private let document = FlippedView()
    private var slots: [Slot] = []
    private var lastWidth: CGFloat = 0
    private var layingOut = false
    var anchor: ReadingAnchor?
    var onAnchor: ((ReadingAnchor?) -> Void)?
    var onNotice: ((String) -> Void)?
    private var observation: NSObjectProtocol?
    private var matches: [(Int, NSRange)] = []
    private var matchIndex = -1
    private var activeQuery = ""
    private var returnAnchor: ReadingAnchor?
    var realizedBlockCount: Int { slots.filter { $0.view != nil }.count }

    override init(frame: NSRect) {
        super.init(frame: frame)
        documentView = document
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = Ocean.surface
        contentView.postsBoundsChangedNotifications = true
        observation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main
        ) { [weak self] _ in self?.didScroll() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }

    func show(
        _ conversation: Conversation, settings: ReadingSettings, anchor: ReadingAnchor?,
        preservingSearch: Bool = false
    ) {
        let query = preservingSearch ? activeQuery : ""
        let savedReturn = preservingSearch ? returnAnchor : nil
        let selectedMatch: ReadingAnchor? =
            preservingSearch && matches.indices.contains(matchIndex)
            ? {
                let (index, range) = matches[matchIndex]
                return ReadingAnchor(
                    messageID: slots[index].messageID, block: slots[index].index, character: range.location)
            }() : nil
        layingOut = true
        for view in document.subviews { view.removeFromSuperview() }
        slots = []
        matches = []
        matchIndex = -1
        returnAnchor = nil
        activeQuery = ""
        for message in conversation.messages {
            slots.append(
                Slot(
                    messageID: message.id, index: -1,
                    block: .paragraph(message.role.uppercased()), fontSize: 11, height: 40))
            for (index, block) in MarkdownBlocks.parse(message.text).enumerated() {
                slots.append(
                    Slot(messageID: message.id, index: index, block: block, fontSize: settings.fontSize))
            }
        }
        self.anchor = anchor
        lastWidth = contentSize.width
        positionSlots()
        layingOut = false
        restore(anchor)
        if !query.isEmpty {
            activeQuery = query
            returnAnchor = savedReturn
            collectMatches(query)
            matchIndex =
                matches.firstIndex { index, range in
                    slots[index].messageID == selectedMatch?.messageID
                        && slots[index].index == selectedMatch?.block
                        && range.location == selectedMatch?.character
                } ?? -1
        }
    }

    override func layout() {
        super.layout()
        guard contentSize.width > 0, abs(lastWidth - contentSize.width) > 0.5, !layingOut else { return }
        lastWidth = contentSize.width
        restore(anchor)
    }

    private func positionSlots() {
        let width = contentSize.width
        let margin: CGFloat = width < 350 ? 20 : 32
        var y: CGFloat = 28
        for index in slots.indices {
            slots[index].frame = NSRect(
                x: margin, y: y, width: max(100, width - margin * 2), height: slots[index].height)
            slots[index].view?.frame = slots[index].frame
            y += slots[index].height
        }
        document.sortSubviews(
            { left, right, _ in
                if left.frame.minY == right.frame.minY { return .orderedSame }
                return left.frame.minY < right.frame.minY ? .orderedAscending : .orderedDescending
            }, context: nil)
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(contentSize.height, y + 30))
    }

    private func realize(_ index: Int) {
        if slots[index].view == nil {
            let slot = slots[index]
            let view = ReadingBlock(
                messageID: slot.messageID, index: slot.index, block: slot.block, fontSize: slot.fontSize)
            slots[index].measuredWidth = 0
            if let image = slots[index].selectedImage { view.installImage(image) }
            view.onGeometryChange = { [weak self, weak view] in
                guard let self, self.slots.indices.contains(index), self.slots[index].view === view else {
                    return
                }
                self.slots[index].selectedImage = view?.previewImage
                self.slots[index].measuredWidth = 0
                self.updateViewport(keeping: self.anchor)
            }
            slots[index].view = view
            document.addSubview(view)
        }
        let width = slots[index].frame.width
        if slots[index].measuredWidth != width {
            slots[index].height =
                slots[index].view!.arrange(width: width) + (slots[index].index == -1 ? 16 : 0)
            slots[index].measuredWidth = width
        }
    }

    private func anchorIndex(_ anchor: ReadingAnchor) -> Int? {
        slots.firstIndex { $0.messageID == anchor.messageID && $0.index == anchor.block }
            ?? slots.firstIndex { $0.messageID == anchor.messageID && $0.index >= 0 }
    }

    /// Measurement changes estimated heights. Keep the same character at the top throughout.
    private func updateViewport(keeping saved: ReadingAnchor?) {
        guard !layingOut else { return }
        layingOut = true
        defer { layingOut = false }
        let target = saved.flatMap(anchorIndex)
        if let target { realize(target) }
        positionSlots()
        func scrollToSaved() {
            if let saved, let target, let view = slots[target].view {
                let y = slots[target].frame.minY + view.y(character: saved.character) + saved.offset
                contentView.scroll(
                    to: NSPoint(x: 0, y: min(max(0, y), max(0, document.frame.height - contentSize.height))))
            }
        }
        scrollToSaved()
        // Two passes settle newly measured blocks around the requested character.
        for _ in 0..<2 {
            let area = contentView.bounds.insetBy(dx: 0, dy: -contentSize.height)
            for index in slots.indices where slots[index].frame.intersects(area) { realize(index) }
            positionSlots()
            scrollToSaved()
        }
        let keep = contentView.bounds.insetBy(dx: 0, dy: -contentSize.height * 2)
        for index in slots.indices where !slots[index].frame.intersects(keep) && index != target {
            slots[index].view?.removeFromSuperview()
            slots[index].view = nil
            // Height remains cached; a future width change invalidates it on demand.
        }
        reflectScrolledClipView(contentView)
    }

    private func didScroll() {
        guard !layingOut, abs(lastWidth - contentSize.width) < 0.5 else { return }
        let saved = visibleAnchor()
        updateViewport(keeping: saved)
        anchor = visibleAnchor()
        onAnchor?(anchor)
    }

    func visibleAnchor() -> ReadingAnchor? {
        let top = contentView.bounds.minY
        guard let slot = slots.first(where: { $0.index >= 0 && $0.frame.maxY > top }) else { return nil }
        let character = slot.view?.character(at: top - slot.frame.minY) ?? 0
        let offset = top - slot.frame.minY - (slot.view?.y(character: character) ?? 0)
        return ReadingAnchor(
            messageID: slot.messageID, block: slot.index, character: character, offset: offset)
    }

    func restore(_ anchor: ReadingAnchor?) {
        var restored = anchor
        if let anchor, anchorIndex(anchor) == nil {
            restored = nil
            onNotice?(
                localized(
                    "Saved message is no longer available. Showing the beginning of this history.",
                    "原来阅读的消息已不可用，已显示对话开头。"))
        }
        if restored == nil {
            layingOut = true
            contentView.scroll(to: .zero)
            layingOut = false
        }
        updateViewport(keeping: restored)
        self.anchor = restored ?? visibleAnchor()
    }

    private func collectMatches(_ query: String) {
        // Search source blocks even when their native views are not realized.
        matches = []
        for index in slots.indices where slots[index].index >= 0 {
            let text = ReadingBlock.searchableText(slots[index].block) as NSString
            var range = NSRange(location: 0, length: text.length)
            while range.length > 0 {
                let found = text.range(of: query, options: [.caseInsensitive], range: range)
                if found.location == NSNotFound { break }
                matches.append((index, found))
                range = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
            }
        }
    }
    var findStatus: String? {
        guard !activeQuery.isEmpty else { return nil }
        guard !matches.isEmpty else { return localized("No matches", "没有匹配内容") }
        if matchIndex < 0 {
            return localized("\(matches.count) matches · Next to locate", "\(matches.count) 处匹配 · 点击下一个定位")
        }
        return localized(
            "\(matchIndex + 1) / \(matches.count) · Clear to return",
            "\(matchIndex + 1) / \(matches.count) · 清除后返回原位")
    }

    @discardableResult func search(_ query: String, next: Bool = false) -> String {
        if !next {
            activeQuery = query
            if returnAnchor == nil { returnAnchor = anchor }
            matches = []
            matchIndex = -1
            for slot in slots { slot.view?.textView?.setSelectedRange(NSRange(location: 0, length: 0)) }
            if query.isEmpty {
                restore(returnAnchor)
                returnAnchor = nil
                return ""
            }
            collectMatches(query)
        }
        guard !matches.isEmpty else { return localized("No matches", "没有匹配内容") }
        matchIndex = (matchIndex + 1) % matches.count
        let (index, range) = matches[matchIndex]
        let slot = slots[index]
        restore(ReadingAnchor(messageID: slot.messageID, block: slot.index, character: range.location))
        slots[index].view?.textView?.setSelectedRange(range)
        onAnchor?(anchor)
        return localized(
            "\(matchIndex + 1) / \(matches.count) · Clear to return",
            "\(matchIndex + 1) / \(matches.count) · 清除后返回原位")
    }
}
