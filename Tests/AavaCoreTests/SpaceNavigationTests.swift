import XCTest
@testable import AavaCore

final class SpaceNavigationTests: XCTestCase {
    func testWrappingAndEmptySpaces() {
        XCTAssertEqual(SpaceNavigation.destination(current: 2, count: 3, step: 1), 0)
        XCTAssertEqual(SpaceNavigation.destination(current: 0, count: 3, step: -1), 2)
        XCTAssertEqual(SpaceNavigation.destination(current: 0, count: 3, step: -7), 2)
        XCTAssertNil(SpaceNavigation.destination(current: 0, count: 0, step: 1))
        XCTAssertNil(SpaceNavigation.destination(current: 0, count: 1, step: 1))
        XCTAssertNil(SpaceNavigation.destination(current: 0, count: 3, step: 0))
    }
    func testOneSpacePerTrackpadGestureAndNoMomentumSkip() {
        var swipe = SpaceSwipeAccumulator()
        XCTAssertNil(swipe.consume(x: -20, y: 1, time: 0, began: true, ended: false, momentum: false, phased: true).step)
        XCTAssertEqual(swipe.consume(x: -30, y: 1, time: 0.02, began: false, ended: false, momentum: false, phased: true).step, 1)
        XCTAssertNil(swipe.consume(x: -200, y: 0, time: 0.1, began: false, ended: false, momentum: false, phased: true).step)
        _ = swipe.consume(x: 0, y: 0, time: 0.2, began: false, ended: true, momentum: false, phased: true)
        let tail = swipe.consume(x: -200, y: 0, time: 0.3, began: false, ended: false, momentum: true, phased: false)
        XCTAssertNil(tail.step)
        XCTAssertTrue(tail.consumed, "The same swipe must not scroll the emoji strip during momentum")
        XCTAssertEqual(swipe.consume(x: 50, y: 0, time: 0.4, began: true, ended: false, momentum: false, phased: true).step, -1)
    }
    func testVerticalScrollingAndDiagonalNoiseStayInContent() {
        var swipe = SpaceSwipeAccumulator()
        let vertical = swipe.consume(x: 4, y: 30, time: 0, began: true, ended: false, momentum: false, phased: true)
        XCTAssertFalse(vertical.consumed)
        XCTAssertNil(swipe.consume(x: -200, y: 0, time: 0.1, began: false, ended: false, momentum: false, phased: true).step)
        swipe.reset()
        XCTAssertNil(swipe.consume(x: -20, y: 19, time: 1, began: true, ended: false, momentum: false, phased: true).step)
    }
    func testUnphasedWheelNeedsANewBurst() {
        var swipe = SpaceSwipeAccumulator()
        XCTAssertEqual(swipe.consume(x: -60, y: 0, time: 0, began: false, ended: false, momentum: false, phased: false).step, 1)
        XCTAssertNil(swipe.consume(x: -60, y: 0, time: 0.1, began: false, ended: false, momentum: false, phased: false).step)
        XCTAssertEqual(swipe.consume(x: 60, y: 0, time: 0.5, began: false, ended: false, momentum: false, phased: false).step, -1)
    }
}

extension SpaceNavigationTests {
    func testShortHorizontalScrollChangesSpaceButDiagonalAndMomentumDoNotSkip() {
        var swipe = SpaceSwipeAccumulator()
        XCTAssertEqual(swipe.consume(x: -34, y: 2, time: 0, began: true, ended: false, momentum: false, phased: true).step, 1)
        XCTAssertNil(swipe.consume(x: -100, y: 0, time: 0.1, began: false, ended: false, momentum: true, phased: true).step)
        XCTAssertEqual(swipe.consume(x: 34, y: 0, time: 0.4, began: true, ended: false, momentum: false, phased: true).step, -1)
        XCTAssertNil(swipe.consume(x: -20, y: 40, time: 1, began: true, ended: false, momentum: false, phased: true).step)
    }
}
