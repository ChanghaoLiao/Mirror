import AppKit
import XCTest

@testable import Mirror

final class BlackboardOpeningTests: XCTestCase {
    private func area(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for i in polygon.indices {
            let next = polygon[(i + 1) % polygon.count]
            sum += polygon[i].x * next.y - polygon[i].y * next.x
        }
        return abs(sum) / 2
    }
    func testFullWhiteStartAndCompleteDiagonalReveal() {
        XCTAssertEqual(area(BlackboardOpening.remaining(at: 0)), 1, accuracy: 0.00001)
        XCTAssertEqual(area(BlackboardOpening.remaining(at: 0.5)), 0.5, accuracy: 0.00001)
        XCTAssertTrue(BlackboardOpening.remaining(at: 1).isEmpty)
        XCTAssertTrue(BlackboardOpening.remaining(at: 2).isEmpty)
        XCTAssertEqual(BlackboardOpening.duration, 1.2)
    }
    func testDiagonalCoverageNeverReturnsOrLeavesAnUncoveredCorner() {
        var previousArea: CGFloat = 1
        for step in 0...1200 {
            let progress = CGFloat(step) / 1200
            let polygon = BlackboardOpening.remaining(at: progress)
            let currentArea = area(polygon)
            XCTAssertLessThanOrEqual(currentArea, previousArea + 0.00001)
            previousArea = currentArea
            let edge = 2 * BlackboardOpening.motion(at: progress).x
            for point in polygon {
                XCTAssertGreaterThanOrEqual(point.x, 0)
                XCTAssertLessThanOrEqual(point.x, 1.00001)
                XCTAssertGreaterThanOrEqual(point.y, 0)
                XCTAssertLessThanOrEqual(point.y, 1.00001)
                XCTAssertGreaterThanOrEqual(point.x + point.y + 0.00001, edge)
            }
        }
        XCTAssertEqual(previousArea, 0)
    }
    func testEraserMovesContinuouslyAlongOneDiagonalWithoutReversing() {
        var previous = BlackboardOpening.motion(at: 0)
        XCTAssertEqual(previous.x, 0)
        for step in 1...1200 {
            let current = BlackboardOpening.motion(at: CGFloat(step) / 1200)
            XCTAssertEqual(current.x, current.y)
            XCTAssertGreaterThanOrEqual(current.x, previous.x)
            XCTAssertLessThan(abs(current.x - previous.x), 0.004)
            previous = current
        }
        XCTAssertEqual(previous.x, 1, accuracy: 0.00001)
        XCTAssertEqual(previous.y, 1, accuracy: 0.00001)
    }
}
