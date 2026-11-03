import AppKit
import MirrorCore
import XCTest

@testable import Mirror

final class TypographyTests: XCTestCase {
    @MainActor func testTypographyKeepsStyledTextSelectionLinksAndFontTraits() throws {
        let original = MirrorPreferences.blackboard
        MirrorPreferences.blackboard = true
        defer { MirrorPreferences.blackboard = original }
        let block = ReadingBlock(
            messageID: "m", index: 0,
            block: .paragraph("中文 **bold** *italic* `code` [link](https://example.com)"), fontSize: 23)
        let text = try XCTUnwrap(block.textView)
        let storage = try XCTUnwrap(text.textStorage)
        let saved = NSAttributedString(attributedString: storage)
        text.setSelectedRange(NSRange(location: 1, length: 3))
        block.updateFontSize(24)
        XCTAssertEqual(storage.string, saved.string)
        XCTAssertEqual(text.selectedRange(), NSRange(location: 1, length: 3))
        saved.enumerateAttribute(.font, in: NSRange(location: 0, length: saved.length)) { value, range, _ in
            guard let old = value as? NSFont,
                let new = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            else { return XCTFail("font") }
            XCTAssertEqual(new.pointSize, old.pointSize + 1)
            XCTAssertEqual(new.fontName, old.fontName)
        }
        block.updateFontSize(23)
        XCTAssertTrue(storage.isEqual(to: saved))
    }
    @MainActor func testImageAndRoleAreNotReplacedByTypography() {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        let block = ReadingBlock(messageID: "m", index: 0, block: .image("sample", "unused"), fontSize: 23)
        block.installImage(image)
        block.updateFontSize(24)
        XCTAssertTrue(block.previewImage === image)
        XCTAssertGreaterThan(block.arrange(width: 400), 0)
        let role = ReadingBlock(messageID: "m", index: -1, block: .paragraph("ASSISTANT"), fontSize: 11)
        let before = role.textView?.font
        role.updateFontSize(24)
        XCTAssertEqual(role.textView?.font, before)
    }
    @MainActor func testReaderRetainsNativeViewsSearchAndAnchorDuringFontChange() throws {
        let reader = ConversationReader(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let conversation = Conversation(
            summary: .init(id: "m", title: "Test"),
            messages: [
                .init(
                    id: "one", role: "assistant",
                    text: String(repeating: "中文定位词 **bold** English\n\n", count: 12))
            ])
        reader.show(conversation, settings: ReadingSettings(), anchor: nil)
        _ = reader.search("定位词", next: false)
        let anchor = try XCTUnwrap(reader.anchor)
        let first = try XCTUnwrap(
            reader.documentView?.subviews.compactMap { $0 as? ReadingBlock }.first {
                $0.index == anchor.block
            })
        reader.updateFontSize(24)
        XCTAssertEqual(reader.anchor?.messageID, anchor.messageID)
        XCTAssertEqual(reader.anchor?.block, anchor.block)
        XCTAssertEqual(reader.anchor?.character, anchor.character)
        XCTAssertTrue(reader.documentView?.subviews.contains { $0 === first } == true)
        _ = reader.search("定位词", next: true)
        XCTAssertNotEqual(reader.anchor, anchor)
    }
}
