import AppKit
import CoreGraphics
import XCTest

@testable import Mirror

final class ReferenceEventTests: XCTestCase {
    @MainActor func testPointerEventsReachTheirNativeViewsAndEstablishHumanPriority() throws {
        // Real non-keyboard NSEvents reject keyboard-only accessors. This also protects
        // Command-scroll and dragging, which must not enter shortcut handling.
        for command in [false, true] {
            let flags: NSEvent.ModifierFlags = command ? [.command] : []
            let wheel = try XCTUnwrap(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: -64, wheel2: 0, wheel3: 0))
            wheel.flags = command ? [.maskCommand] : []
            var events = [try XCTUnwrap(NSEvent(cgEvent: wheel))]
            for type in [NSEvent.EventType.leftMouseDragged, .rightMouseDown] {
                events.append(try mouse(type, flags: flags))
            }
            for event in events {
                var interactions = 0
                let result = ReferenceEventRouter.route(
                    event, humanDidInteract: { interactions += 1 },
                    dismissIfOutside: { _ in XCTFail("Only a left click can dismiss an overlay") },
                    perform: { _ in XCTFail("Pointer input must not invoke keyboard actions") })
                XCTAssertTrue(result === event, "The original event must reach the native view")
                XCTAssertEqual(interactions, 1)
            }
        }
    }

    @MainActor func testRecognizedShortcutsRunAfterHumanPriorityAndConsumeOnlyTheirKeyEvent() throws {
        let cases: [(String, ReferenceEventRouter.Action)] = [
            ("d", .duplicate), ("f", .find), ("r", .refresh), ("w", .close), ("n", .open),
        ]
        for (character, expected) in cases {
            let event = try key(character, flags: [.command])
            var interactions = 0
            var actions: [ReferenceEventRouter.Action] = []
            let result = ReferenceEventRouter.route(
                event, humanDidInteract: { interactions += 1 },
                dismissIfOutside: { _ in XCTFail("Keyboard input is not a pointer click") },
                perform: { action in
                    XCTAssertEqual(interactions, 1, "Human input must invalidate Agent work first")
                    actions.append(action)
                })
            XCTAssertNil(result)
            XCTAssertEqual(actions, [expected])
        }
    }

    @MainActor func testOrdinaryKeysAndOtherCommandShortcutsKeepNativeHandling() throws {
        for event in [
            try key("f"), try key("c", flags: [.command]),
            try key("f", type: .keyUp, flags: [.command]),
        ] {
            var interactions = 0
            let result = ReferenceEventRouter.route(
                event, humanDidInteract: { interactions += 1 },
                dismissIfOutside: { _ in XCTFail("Unexpected pointer handling") },
                perform: { _ in XCTFail("Native text handling must be preserved") })
            XCTAssertTrue(result === event)
            XCTAssertEqual(interactions, 1)
        }
    }

    @MainActor func testLeftClickDismissalDoesNotConsumeTheClick() throws {
        let event = try mouse(.leftMouseDown)
        var calls: [String] = []
        let result = ReferenceEventRouter.route(
            event, humanDidInteract: { calls.append("human") },
            dismissIfOutside: { click in
                XCTAssertTrue(click === event)
                calls.append("dismissIfOutside")
            },
            perform: { _ in XCTFail("A click cannot invoke a shortcut") })
        XCTAssertTrue(result === event)
        XCTAssertEqual(calls, ["human", "dismissIfOutside"])
    }

    @MainActor func testEscapeDismissesTheOverlayWithoutACommandModifier() throws {
        let event = try key("\u{1b}", keyCode: 53)
        var actions: [ReferenceEventRouter.Action] = []
        XCTAssertNil(
            ReferenceEventRouter.route(
                event, humanDidInteract: {}, dismissIfOutside: { _ in },
                perform: { actions.append($0) }))
        XCTAssertEqual(actions, [.dismiss])
    }

    private func mouse(
        _ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
    }

    private func key(
        _ character: String, type: NSEvent.EventType = .keyDown,
        flags: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
    }
}
