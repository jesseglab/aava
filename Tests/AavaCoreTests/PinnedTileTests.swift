import XCTest
@testable import AavaCore

final class PinnedTileTests: XCTestCase {
    func testMixedWidthsWrapWithoutOverlappingOrReordering() {
        let positions = PinnedTilePacking.positions([1, 2, 2, 1, 1, 2])
        XCTAssertEqual(positions.map(\.row), [0, 0, 1, 1, 1, 2])
        XCTAssertEqual(positions.map(\.column), [0, 1, 0, 2, 3, 0])
        var occupied = Set<String>()
        for item in positions {
            XCTAssertLessThanOrEqual(item.column + item.span, 4)
            for column in item.column..<(item.column + item.span) { XCTAssertTrue(occupied.insert("\(item.row):\(column)").inserted) }
        }
        XCTAssertTrue(PinnedTilePacking.positions([]).isEmpty)
        XCTAssertEqual(PinnedTilePacking.positions([0, 3, -1]).map(\.span), [1, 1, 1])
    }
    func testOldPinnedTabsRemainCompactAndRetainOriginalTitle() throws {
        let json = "{\"id\":\"\(UUID().uuidString)\",\"title\":\"GitHub\",\"pinned\":true}"
        let tab = try JSONDecoder().decode(BrowserTab.self, from: Data(json.utf8))
        XCTAssertNil(tab.tile)
        XCTAssertEqual(tab.displayTitle, "GitHub")
        XCTAssertEqual(PinnedTileStyle(span: 100, tint: "#bad").columns, 1)
        XCTAssertNil(PinnedTileStyle(tint: "#bad").validTint)
        XCTAssertEqual(PinnedTileStyle(tint: "abcdef").validTint, "ABCDEF")
    }
    func testAliasSurvivesNavigationAndArchiveWithoutRenamingThePage() throws {
        var state = BrowserState()
        let id = state.spaces[0].tabs[0].id
        state.spaces[0].tabs[0].pinned = true
        state.spaces[0].tabs[0].tile = PinnedTileStyle(span: 2, name: "My work", tint: "C3749E")
        state.updateTab(id, url: URL(string: "https://example.com/work"), title: "Updated page title")
        XCTAssertEqual(state.spaces[0].tabs[0].displayTitle, "My work")
        XCTAssertEqual(state.spaces[0].tabs[0].title, "Updated page title")
        XCTAssertEqual(CommandSearch.results(query: "my work", in: state.spaces[0]).first?.target, id)
        state.archiveTab(id, reason: .closed)
        let saved = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        var restored = saved
        let archive = try XCTUnwrap(restored.spaces[0].archive?.first)
        let newID = try XCTUnwrap(restored.restoreArchive(archive.id))
        let tab = try XCTUnwrap(restored.spaces[0].tabs.first { $0.id == newID })
        XCTAssertEqual(tab.tile, PinnedTileStyle(span: 2, name: "My work", tint: "C3749E"))
        XCTAssertNil(restored.spaces[1].tabs.first?.tile)
    }
    func testCompactWidthPreservesCustomizationForLaterExpansion() {
        var tab = BrowserTab(title: "Original", pinned: true)
        tab.tile = PinnedTileStyle(span: 2, name: "Workspace", tint: "AABBCC")
        tab.tile?.span = 1
        XCTAssertEqual(tab.tile?.name, "Workspace")
        XCTAssertEqual(tab.tile?.validTint, "AABBCC")
        tab.pinned = false
        XCTAssertEqual(tab.displayTitle, "Original")
    }
    func testFaviconTintSkipsTransparentAndNeutralPixels() {
        let neutral: [UInt8] = [255,255,255,255, 0,0,0,255, 0,0,0,0]
        XCTAssertEqual(FaviconTint.extract(neutral), FaviconTint.fallback)
        XCTAssertEqual(FaviconTint.extract(neutral + [220,30,50,255]), "DC1E32")
        XCTAssertEqual(FaviconTint.extract([128,0,0,128]), "FF0000")
        XCTAssertEqual(FaviconTint.extract([1]), FaviconTint.fallback)
    }
    func testDominantFaviconHueDoesNotBlendOpposingColorsToBrown() {
        let pixels: [UInt8] = [255,0,0,255, 255,0,0,255, 0,255,0,255]
        XCTAssertEqual(FaviconTint.extract(pixels), "FF0000")
    }
}
