import XCTest
@testable import AavaCore

final class BrowserDownloadsTests: XCTestCase {
    func testDownloadsStayInTheirOwnSpaceAndCompleteOnce() {
        var state = BrowserState()
        let profile = state.spaces[1].profileID
        var item = BrowserDownload(id: "run-1", profile: profile, name: "Report.pdf", received: 20, total: 100, status: .downloading)
        XCTAssertFalse(state.updateDownload(item))
        XCTAssertNil(state.spaces[0].downloads)
        XCTAssertEqual(state.spaces[1].downloads?.first?.progress, 0.2)
        item.received = 100; item.status = .complete
        XCTAssertTrue(state.updateDownload(item))
        XCTAssertFalse(state.updateDownload(item))
        XCTAssertEqual(state.spaces[1].downloads?.count, 1)
        XCTAssertFalse(state.updateDownload(BrowserDownload(id: "foreign", profile: UUID(), name: "Other", status: .complete)))
    }
    func testRestartDoesNotPretendOldDownloadsAreRunning() throws {
        var state = BrowserState(); let profile = state.spaces[0].profileID
        state.updateDownload(BrowserDownload(id: "a", profile: profile, name: "Active", status: .downloading))
        state.updateDownload(BrowserDownload(id: "b", profile: profile, name: "Paused", status: .paused))
        state.updateDownload(BrowserDownload(id: "c", profile: profile, name: "Done", status: .complete))
        var restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        restored.recoverDownloadsAfterRestart()
        XCTAssertEqual(restored.spaces[0].downloads?.filter { $0.status == .interrupted }.count, 2)
        XCTAssertEqual(restored.spaces[0].downloads?.filter { $0.status == .complete }.count, 1)
    }
    func testHistoryBoundDoesNotDropActiveDownloads() {
        var state = BrowserState(); let profile = state.spaces[0].profileID
        state.updateDownload(BrowserDownload(id: "active", profile: profile, name: "Active", status: .paused))
        for i in 0..<100 { state.updateDownload(BrowserDownload(id: "done-\(i)", profile: profile, name: "Done", status: .complete)) }
        XCTAssertEqual(state.spaces[0].downloads?.count, 81)
        XCTAssertTrue(state.spaces[0].downloads?.contains { $0.id == "active" } == true)
        XCTAssertNil(BrowserDownload(id: "unknown", profile: profile, name: "Unknown size", status: .downloading).progress)
    }
}
