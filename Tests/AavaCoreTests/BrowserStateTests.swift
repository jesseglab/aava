import XCTest
@testable import AavaCore

final class BrowserStateTests: XCTestCase {
    func testProfilesAreSeparateAndInitialTabsAreUnloaded() {
        let state = BrowserState()
        XCTAssertEqual(Set(state.spaces.map(\.profileID)).count, 3)
        XCTAssertTrue(state.spaces.flatMap(\.tabs).allSatisfy { $0.url == nil })
    }
    func testClosingLastTabLeavesUsableStartPage() {
        var state = BrowserState()
        state.closeTab(state.currentTab!.id)
        XCTAssertEqual(state.currentSpace.tabs.count, 1)
        XCTAssertNotNil(state.currentTab)
        XCTAssertNil(state.currentTab?.url)
    }
    func testTabOperationsDoNotLeakAcrossSpaces() {
        var state = BrowserState()
        let work = state.selectedSpaceID
        let tab = state.addTab(url: URL(string: "https://example.com"))
        state.selectedSpaceID = state.spaces[1].id
        XCTAssertEqual(state.currentSpace.tabs.count, 1)
        state.updateTab(tab, url: URL(string: "https://example.com/next"), title: "Next")
        XCTAssertEqual(state.currentSpace.tabs.count, 1)
        state.selectedSpaceID = work
        XCTAssertEqual(state.currentTab?.title, "Next")
    }
    func testRecursiveFolderDeletionKeepsUnrelatedItems() {
        var state = BrowserState()
        let extra = SavedItem(title: "Keep", url: URL(string: "https://example.com"))
        state.spaces[0].saved.append(extra)
        let root = state.spaces[0].saved.first!.id
        state.deleteSaved(root)
        XCTAssertEqual(state.spaces[0].saved, [extra])
    }
    func testURLAndSearchResolution() {
        XCTAssertEqual(NavigationInput.resolve(" example.com/path ")?.absoluteString, "https://example.com/path")
        XCTAssertEqual(NavigationInput.resolve("http://localhost:8000")?.scheme, "http")
        let search = NavigationInput.resolve("a & b + c")!
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a & b + c")
        XCTAssertNil(NavigationInput.resolve("javascript:alert(1)"))
        XCTAssertNil(NavigationInput.resolve("file:///private/test"))
        XCTAssertNil(NavigationInput.resolve(" "))
    }
    func testStateRoundTripPreservesSpacesFoldersAndProfiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StateRepository(fileURL: directory.appendingPathComponent("state.json"))
        var state = BrowserState()
        state.spaces[1].theme = .sage
        state.spaces[1].iconStyle = .emoji
        state.addTab(url: URL(string: "https://example.com"))
        try repository.save(state)
        XCTAssertEqual(try repository.load(), state)
    }
    func testInvalidSelectionIsRepaired() {
        var state = BrowserState()
        state.selectedSpaceID = UUID(); state.spaces[0].selectedTabID = UUID()
        state.normalize()
        XCTAssertEqual(state.selectedSpaceID, state.spaces[0].id)
        XCTAssertNotNil(state.currentTab)
    }
    func testInvalidFileIsReportedRatherThanSilentlyReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try StateRepository(fileURL: url).load())
    }
}
