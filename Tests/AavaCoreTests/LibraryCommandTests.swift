import XCTest
@testable import AavaCore

final class LibraryCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testClosedPageRestoresWithTitleAndPinInOriginalSpace() throws {
        var state = BrowserState()
        let id = state.addTab(url: URL(string: "https://example.com/a"))
        state.spaces[0].tabs[state.spaces[0].tabs.count - 1].pinned = true
        state.updateTab(id, url: nil, title: "Research")
        state.archiveTab(id, reason: .closed, now: now)
        let archive = try XCTUnwrap(state.spaces[0].archive?.first)
        state.selectedSpaceID = state.spaces[1].id
        XCTAssertNil(state.restoreArchive(archive.id))
        XCTAssertNil(state.spaces[1].archive)
        state.selectedSpaceID = state.spaces[0].id
        let restored = try XCTUnwrap(state.restoreArchive(archive.id, now: now))
        XCTAssertNotEqual(restored, id)
        XCTAssertEqual(state.currentTab?.title, "Research")
        XCTAssertEqual(state.currentTab?.pinned, true)
        XCTAssertTrue(state.currentSpace.archive!.isEmpty)
    }
    func testEmptyTabDoesNotFillArchive() {
        var state = BrowserState(); state.archiveTab(state.currentTab!.id, reason: .clean)
        XCTAssertTrue(state.currentSpace.archive?.isEmpty ?? true)
        XCTAssertEqual(state.currentSpace.tabs.count, 1)
    }
    func testHistoryRejectsInternalPagesAndDeduplicatesVisitsWithinSpace() {
        var state = BrowserState(); let id = state.currentTab!.id, url = URL(string: "https://example.com")!
        state.recordVisit(id, url: URL(string: "chrome://extensions")!, now: now)
        XCTAssertNil(state.currentSpace.history)
        state.recordVisit(id, url: url, now: now); state.recordVisit(id, url: url, now: now.addingTimeInterval(1))
        XCTAssertEqual(state.currentSpace.history?.count, 1)
        XCTAssertEqual(state.currentSpace.history?.first?.visits, 2)
        XCTAssertNil(state.spaces[1].history)
    }
    func testCleanupKeepsCurrentPinnedProtectedAndDistinctQueryParameters() {
        var space = BrowserSpace(name: "Test", emoji: "🌊", theme: .tide)
        let url = URL(string: "https://example.com?q=a")!
        let current = BrowserTab(url: url), duplicate = BrowserTab(url: url), pinned = BrowserTab(url: url, pinned: true)
        let protected = BrowserTab(url: url), different = BrowserTab(url: URL(string: "https://example.com?q=b")), blank = BrowserTab()
        space.tabs = [duplicate, pinned, current, protected, different, blank]; space.selectedTabID = current.id
        XCTAssertEqual(TabCleanup.cleanable(in: space, protected: [protected.id]), [duplicate.id, blank.id])
    }
    func testAutoArchiveUsesLastActivityAndExcludesProtectedTabs() {
        var space = BrowserSpace(name: "Test", emoji: "🌊", theme: .tide)
        var expired = BrowserTab(url: URL(string: "https://example.com")); expired.lastActiveAt = now.addingTimeInterval(-12 * 3600)
        var active = expired; active.id = UUID()
        var pinned = expired; pinned.id = UUID(); pinned.pinned = true
        var call = expired; call.id = UUID()
        var missingDate = expired; missingDate.id = UUID(); missingDate.lastActiveAt = nil
        space.tabs = [expired, active, pinned, call, missingDate]; space.selectedTabID = active.id
        XCTAssertTrue(TabCleanup.expired(in: space, now: now).isEmpty)
        space.autoArchiveHours = 12
        XCTAssertEqual(TabCleanup.expired(in: space, now: now, protected: [call.id]), [expired.id])
    }
    func testTidyIsStableAndDoesNotCloseOrSelectTabs() {
        var state = BrowserState()
        let z = BrowserTab(url: URL(string: "https://z.com")), a = BrowserTab(url: URL(string: "https://a.com/a")), a2 = BrowserTab(url: URL(string: "https://a.com/b")), pin = BrowserTab(url: URL(string: "https://z.com"), pinned: true)
        state.spaces[0].tabs = [z, a, pin, a2]; state.spaces[0].selectedTabID = z.id
        state.tidyTabs()
        XCTAssertEqual(state.currentSpace.tabs.map(\.id), [pin.id, a.id, a2.id, z.id])
        XCTAssertEqual(state.currentTab?.id, z.id)
        XCTAssertNil(state.currentSpace.archive)
    }
    func testSearchUsesOnlySuppliedSpaceAndRanksOpenTabs() {
        var state = BrowserState()
        let open = state.addTab(url: URL(string: "https://linear.app")); state.updateTab(open, url: nil, title: "Linear")
        state.spaces[0].history = [HistoryEntry(url: URL(string: "https://linear.app/old")!, title: "Linear old")]
        let results = CommandSearch.results(query: "lin", in: state.currentSpace)
        XCTAssertEqual(results.first?.target, open)
        XCTAssertEqual(results[1].kind, .navigate)
        XCTAssertTrue(results.contains { $0.kind == .history })
        XCTAssertFalse(CommandSearch.results(query: "lin", in: state.spaces[1]).contains { $0.kind == .tab || $0.kind == .history })
    }
    func testNumberDotSelectsTabAndActionsCanBeFound() {
        let state = BrowserState()
        XCTAssertEqual(CommandSearch.results(query: "1.", in: state.currentSpace).first?.target, state.currentTab?.id)
        XCTAssertTrue(CommandSearch.results(query: "tidy", in: state.currentSpace).contains { $0.id == "tidy" })
        XCTAssertTrue(CommandSearch.results(query: "git", in: state.currentSpace).contains { $0.id == "github" })
    }
    func testLearningCanPromoteChosenResultWithoutCrossSpaceData() {
        var space = BrowserSpace(name: "Test", emoji: "", theme: .tide)
        let first = BrowserTab(title: "Alpha One", url: URL(string: "https://a.com")), second = BrowserTab(title: "Alpha Two", url: URL(string: "https://b.com"))
        space.tabs = [first, second]
        space.commandSelections = ["alp|tab:" + second.id.uuidString: 5]
        XCTAssertEqual(CommandSearch.results(query: "alp", in: space).first?.target, second.id)
    }
    func testLegacySpaceDecodesWithCleanupOffAndNoLibrary() throws {
        let data = try JSONEncoder().encode(BrowserState())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var spaces = try XCTUnwrap(object["spaces"] as? [[String: Any]])
        var tabs = try XCTUnwrap(spaces[0]["tabs"] as? [[String: Any]])
        tabs[0].removeValue(forKey: "lastActiveAt"); spaces[0]["tabs"] = tabs; object["spaces"] = spaces
        var state = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: object))
        state.normalize()
        XCTAssertNotNil(state.currentTab?.lastActiveAt)
        XCTAssertNil(state.currentSpace.autoArchiveHours)
        XCTAssertNil(state.currentSpace.githubFolder)
        XCTAssertNil(state.currentSpace.history)
    }
    func testLibraryRoundTrip() throws {
        var state = BrowserState(); let id = state.addTab(url: URL(string: "https://example.com"))
        state.recordVisit(id, url: URL(string: "https://example.com")!, now: now)
        state.archiveTab(id, reason: .automatic, now: now)
        XCTAssertEqual(try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state)), state)
    }
}
