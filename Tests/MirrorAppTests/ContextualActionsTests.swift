import AppKit
import XCTest

@testable import Mirror

final class ContextualActionsTests: XCTestCase {
    @MainActor func testEveryActionRemainsReachableWhenToolbarIsHidden() throws {
        let original = MirrorPreferences.blackboard
        defer { MirrorPreferences.blackboard = original }
        for style in [false, true] {
            MirrorPreferences.blackboard = style
            for width in [350.0, 519.0, 520.0, 1120.0] {
                let surface = ReferenceSurface(frame: NSRect(x: 0, y: 0, width: width, height: 590))
                surface.showControls(.actions)
                surface.layoutSubtreeIfNeeded()
                surface.controls.layoutSubtreeIfNeeded()
                let compact = style && width >= 520
                XCTAssertEqual(surface.controls.preferredHeight, compact ? 418 : 562)
                for id in ["refresh", "copy", "smaller", "larger"] {
                    let toolbar = try XCTUnwrap(
                        surface.subviews.compactMap { $0 as? NSButton }.first {
                            $0.identifier?.rawValue == id
                        })
                    let menu = try XCTUnwrap(
                        surface.controls.subviews.compactMap { $0 as? NSButton }.first {
                            $0.identifier?.rawValue == id
                        })
                    XCTAssertEqual(toolbar.isHidden, !compact)
                    XCTAssertEqual(menu.isHidden, compact)
                    XCTAssertFalse(toolbar.isHidden && menu.isHidden)
                }
                let actions = surface.controls.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
                    .sorted { $0.frame.minY < $1.frame.minY }
                for pair in zip(actions, actions.dropFirst()) {
                    XCTAssertEqual(pair.1.frame.minY - pair.0.frame.minY, 36)
                }
            }
        }
    }
}
