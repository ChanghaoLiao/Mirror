import AppKit
import MirrorCore

final class ReferenceControls: OceanView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Mode { case conversations, actions, find }
    var mode: Mode = .actions { didSet { updateMode() } }
    let search = NSSearchField()
    let conversationSearch = NSSearchField()
    let status = NSTextField(wrappingLabelWithString: "")
    let table = NSTableView()
    let more = oceanButton("", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private let tableScroll = NSScrollView()
    private var buttons: [String: OceanButton] = [:]
    private var hasMore = false
    var conversations: [ConversationSummary] = []
    var currentConversationID: String?
    var onQuery: ((String) -> Void)?
    var onSearch: ((String, Bool) -> Void)?
    var onSelect: ((String) -> Void)?
    var onAction: ((String) -> Void)?
    var preferredHeight: CGFloat { mode == .find ? 116 : mode == .conversations ? 390 : 490 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        for view in [titleLabel, search, conversationSearch, tableScroll, more, status] { addSubview(view) }
        search.delegate = self
        conversationSearch.delegate = self
        search.sendsSearchStringImmediately = true
        conversationSearch.sendsSearchStringImmediately = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 36
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(selectConversation)
        table.doubleAction = #selector(selectConversation)
        table.style = .plain
        table.backgroundColor = Ocean.surface
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.drawsBackground = false
        more.target = self
        more.action = #selector(moreConversations)
        more.isHidden = true
        for action in [
            "next", "clear", "duplicate", "refresh", "copy", "smaller", "larger", "collapse", "preferences",
            "setup", "close", "dismiss",
        ] {
            let b = oceanButton("", target: self, action: #selector(performAction(_:)))
            if !["next", "clear", "dismiss"].contains(action) { b.textAlignment = .left }
            b.identifier = NSUserInterfaceItemIdentifier(action)
            buttons[action] = b
            addSubview(b)
        }
        status.font = .systemFont(ofSize: 11)
        status.textColor = Ocean.secondary
        localize()
        updateMode()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func localize() {
        let labels = [
            "next": localized("Next ↵", "下一个 ↵"), "clear": localized("Clear", "清除"),
            "duplicate": localized("Duplicate reference  ⌘D", "复制参考窗口  ⌘D"),
            "refresh": localized("Refresh conversation  ⌘R", "刷新对话  ⌘R"),
            "copy": localized("Copy complete message", "复制当前完整消息"),
            "smaller": localized("Smaller text", "缩小字号"), "larger": localized("Larger text", "放大字号"),
            "collapse": localized("Hide reference", "隐藏参考窗口"),
            "preferences": localized("Appearance & Language…", "外观与语言…"),
            "setup": localized("Setup & Permissions…", "设置与权限…"),
            "close": localized("Close reference  ⌘W", "关闭参考窗口  ⌘W"),
            "dismiss": localized("Back to reading  Esc", "返回阅读  Esc"),
        ]
        for (key, label) in labels {
            buttons[key]?.title = label
            buttons[key]?.setAccessibilityLabel(label)
            buttons[key]?.toolTip = label
        }
        search.placeholderString = localized("Find in this conversation", "查找当前对话")
        conversationSearch.placeholderString = localized("Search conversation titles…", "搜索会话标题…")
        search.setAccessibilityLabel(search.placeholderString)
        conversationSearch.setAccessibilityLabel(conversationSearch.placeholderString)
        more.title = localized("Load more conversations", "加载更多会话")
        table.setAccessibilityLabel(localized("Conversations", "会话列表"))
        titleLabel.textColor = Ocean.text
        updateMode()
        table.reloadData()
    }
    private func updateMode() {
        search.isHidden = mode != .find
        conversationSearch.isHidden = mode != .conversations
        tableScroll.isHidden = mode != .conversations
        for (key, b) in buttons {
            b.isHidden =
                mode == .find
                ? !["next", "clear"].contains(key)
                : mode == .conversations ? key != "dismiss" : ["next", "clear"].contains(key)
        }
        more.isHidden = mode != .conversations || !hasMore
        titleLabel.stringValue =
            mode == .actions
            ? localized("This reference", "当前参考")
            : mode == .conversations
                ? localized("Switch conversation", "切换会话") : localized("Find text", "查找内容")
        needsLayout = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Ocean.border.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        border.lineWidth = 1
        border.stroke()
    }
    override func layout() {
        super.layout()
        let width = bounds.width - 24
        titleLabel.frame = NSRect(x: 12, y: 12, width: width, height: 22)
        if mode == .find {
            search.frame = NSRect(x: 12, y: 40, width: max(65, width - 142), height: 28)
            buttons["next"]?.frame = NSRect(x: bounds.width - 146, y: 38, width: 80, height: 32)
            buttons["clear"]?.frame = NSRect(x: bounds.width - 66, y: 38, width: 54, height: 32)
            status.frame = NSRect(x: 12, y: 80, width: width, height: 28)
        } else if mode == .conversations {
            conversationSearch.frame = NSRect(x: 12, y: 42, width: width, height: 30)
            tableScroll.frame = NSRect(x: 12, y: 80, width: width, height: 180)
            table.tableColumns.first?.width = width
            more.frame = NSRect(x: 12, y: 264, width: width, height: 32)
            status.frame = NSRect(x: 12, y: 300, width: width, height: 42)
            buttons["dismiss"]?.frame = NSRect(x: 12, y: 346, width: width, height: 32)
        } else {
            let actions = [
                "duplicate", "refresh", "copy", "smaller", "larger", "collapse", "preferences", "setup",
                "close", "dismiss",
            ]
            for (i, key) in actions.enumerated() {
                buttons[key]?.frame = NSRect(x: 12, y: 40 + CGFloat(i) * 36, width: width, height: 32)
            }
            status.frame = NSRect(x: 12, y: 406, width: width, height: 72)
        }
        if mode != .conversations { more.frame = .zero }
    }
    func setHasMore(_ value: Bool) {
        hasMore = value
        more.isHidden = mode != .conversations || !value
    }
    func focusFirstAction() { window?.makeFirstResponder(buttons["duplicate"]) }
    @objc private func performAction(_ sender: NSButton) {
        let action = sender.identifier?.rawValue ?? ""
        if action == "clear" {
            search.stringValue = ""
            onSearch?("", false)
        } else {
            onAction?(action)
        }
    }
    @objc private func moreConversations() { onAction?("more") }
    @objc private func selectConversation() {
        guard conversations.indices.contains(table.selectedRow) else { return }
        onSelect?(conversations[table.selectedRow].id)
    }
    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSSearchField) === search {
            onSearch?(search.stringValue, false)
        } else {
            onQuery?(conversationSearch.stringValue)
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), control === search {
            onSearch?(search.stringValue, true)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onAction?("dismiss")
            return true
        }
        if selector == #selector(NSResponder.moveDown(_:)), control === conversationSearch,
            !conversations.isEmpty
        {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            window?.makeFirstResponder(table)
            return true
        }
        return false
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { OceanTableRow() }
    func numberOfRows(in tableView: NSTableView) -> Int { conversations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = conversations[row]
        let field = NSTextField(labelWithString: item.title)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = item.title
        field.font = .systemFont(ofSize: 13)
        field.textColor = item.id == currentConversationID ? Ocean.accentText : Ocean.text
        return field
    }
}

final class OceanTableRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Ocean.accentSoft.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}
