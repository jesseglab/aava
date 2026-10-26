import XCTest
@testable import AavaCore

final class SidebarOrganizationTests: XCTestCase {
    func testFolderMovesRejectCyclesAndNonFolders() {
        var state = BrowserState()
        let root = state.currentSpace.saved[0], child = state.currentSpace.saved[1], page = state.currentSpace.saved[2]
        XCTAssertFalse(state.moveSaved(root.id, to: child.id))
        XCTAssertFalse(state.moveSaved(root.id, to: root.id))
        XCTAssertFalse(state.moveSaved(child.id, to: page.id))
        XCTAssertFalse(state.moveSaved(child.id, to: UUID()))
        XCTAssertTrue(state.moveSaved(page.id, to: root.id))
        XCTAssertEqual(state.currentSpace.saved.first { $0.id == page.id }?.parentID, root.id)
        XCTAssertTrue(state.moveSaved(child.id, to: nil))
    }
    func testRenameAndMoveCannotReachAnotherSpace() {
        var state = BrowserState()
        let id = state.currentSpace.saved[0].id
        state.selectedSpaceID = state.spaces[1].id
        XCTAssertFalse(state.renameSaved(id, title: "Changed"))
        XCTAssertFalse(state.moveSaved(id, to: nil))
        XCTAssertEqual(state.spaces[0].saved[0].title, "Projects")
    }
    func testCollapsedFoldersPersistAndCleanUpAfterDeletion() throws {
        var state = BrowserState()
        let parent = state.currentSpace.saved[0].id, child = state.currentSpace.saved[1].id
        state.toggleFolder(parent); state.toggleFolder(child)
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.currentSpace.collapsedFolderIDs, [parent, child])
        state.deleteSaved(parent)
        XCTAssertEqual(state.currentSpace.collapsedFolderIDs, [])
    }
    func testOlderSessionsWithoutCollapsedStateStillLoad() throws {
        let state = BrowserState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var spaces = try XCTUnwrap(json["spaces"] as? [[String: Any]])
        for index in spaces.indices { spaces[index].removeValue(forKey: "collapsedFolderIDs") }
        json["spaces"] = spaces
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.currentSpace.collapsedFolderIDs)
        XCTAssertEqual(restored.currentSpace.saved, state.currentSpace.saved)
    }
    func testRenameTrimsAndRejectsBlankNames() {
        var state = BrowserState()
        let id = state.currentSpace.saved[0].id
        XCTAssertFalse(state.renameSaved(id, title: "  \n"))
        XCTAssertTrue(state.renameSaved(id, title: "  Design  "))
        XCTAssertEqual(state.currentSpace.saved[0].title, "Design")
    }
}
