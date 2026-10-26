import XCTest
@testable import AavaCore

final class SidebarSizingTests: XCTestCase {
    func testNarrowAndWideWidthsPreservePageRoom() {
        XCTAssertEqual(SidebarSizing.width(-500, container: 800), 160)
        XCTAssertEqual(SidebarSizing.width(900, container: 800), 356)
        XCTAssertEqual(SidebarSizing.width(900, container: 1260), 420)
        XCTAssertEqual(SidebarSizing.width(.nan, container: 1260), 244)
        XCTAssertEqual(SidebarSizing.width(244.49, container: 1260), 244)
        XCTAssertEqual(SidebarSizing.width(244.51, container: 1260), 245)
        XCTAssertEqual(SidebarSizing.width(900, container: 800.5), 356)
        XCTAssertEqual(SidebarSizing.columns(width: 160), 2)
        XCTAssertEqual(SidebarSizing.columns(width: 177), 2)
        XCTAssertEqual(SidebarSizing.columns(width: 178), 3)
        XCTAssertEqual(SidebarSizing.columns(width: 244), 4)
        XCTAssertEqual(SidebarSizing.columns(width: 420), 6)
    }
    func testCollapseRequiresDraggingBeyondHalfTheMinimumWidth() {
        XCTAssertFalse(SidebarSizing.shouldCollapse(proposedWidth: 160))
        XCTAssertFalse(SidebarSizing.shouldCollapse(proposedWidth: 81))
        XCTAssertFalse(SidebarSizing.shouldCollapse(proposedWidth: 80))
        XCTAssertTrue(SidebarSizing.shouldCollapse(proposedWidth: 79.9))
        XCTAssertTrue(SidebarSizing.shouldCollapse(proposedWidth: -20))
        XCTAssertFalse(SidebarSizing.shouldCollapse(proposedWidth: .nan))
        XCTAssertFalse(SidebarSizing.shouldCollapse(proposedWidth: -.infinity))
        // Width remains usable while dragging; collapse uses the raw pointer proposal.
        XCTAssertEqual(SidebarSizing.width(79, container: 1120), 160)
        XCTAssertTrue(SidebarSizing.shouldCollapse(proposedWidth: 244 - 165))
        XCTAssertFalse(SidebarSizing.shouldCollapse(proposedWidth: 244 - 164))
    }
    func testMixedPinnedTilesReflowWithoutLossOrOverlap() {
        let spans = [2, 1, 2, 2, 1, 1, 2, 1, 2]
        for columns in 2...6 {
            let positions = PinnedTilePacking.positions(spans, columns: columns)
            XCTAssertEqual(positions.map(\.span), spans)
            var occupied = Set<String>()
            for item in positions {
                XCTAssertLessThanOrEqual(item.column + item.span, columns)
                for column in item.column..<(item.column + item.span) {
                    XCTAssertTrue(occupied.insert("\(item.row):\(column)").inserted)
                }
            }
        }
    }
}
