import XCTest
@testable import AavaCore

final class ArcImporterTests: XCTestCase {
    private func fixture() throws -> Data {
        let items: [Any] = [
            "p",["id":"p","childrenIds":["pin","folder","split"],"data":["itemContainer":[:]]],
            "u",["id":"u","childrenIds":["today","bad"],"data":["itemContainer":[:]]],
            "pin",["id":"pin","data":["tab":["savedURL":"https://example.org/pin","savedTitle":"Pin"]]],
            "folder",["id":"folder","title":"Clients","childrenIds":["sub"],"data":["list":[:]]],
            "sub",["id":"sub","title":"Research","childrenIds":["saved"],"data":["list":[:]]],
            "saved",["id":"saved","data":["tab":["savedURL":"https://example.org/saved","savedTitle":"Saved"]]],
            "split",["id":"split","childrenIds":["pane"],"data":["splitView":[:]]],
            "pane",["id":"pane","data":["tab":["savedURL":"https://example.org/pane"]]],
            "today",["id":"today","data":["tab":["savedURL":"https://example.org/today"]]],
            "bad",["id":"bad","data":["tab":["savedURL":"javascript:alert(1)"]]]
        ]
        let space: [String:Any] = ["id":"arc-a","title":"Work","profile":["default":true],"newContainerIDs":[["pinned":[:]],"p",["unpinned":[:]],"u"]]
        let second: [String:Any] = ["id":"arc-b","title":"Personal","profile":["default":true],"newContainerIDs":[["unpinned":[:]],"u"]]
        return try JSONSerialization.data(withJSONObject:["sidebar":["containers":[["standalone":["_0":"window"]],["spaces":["arc-a",space,"arc-b",second],"items":items]]]])
    }
    func testPinnedFoldersSubfoldersAndIndependentProfiles() throws {
        let result=try ArcImporter.read(fixture())
        XCTAssertEqual(result.spaces.count,2)
        let work=result.spaces[0]
        XCTAssertEqual(work.tabs.count,2);XCTAssertTrue(work.tabs[0].pinned)
        XCTAssertFalse(work.tabs[1].pinned)
        let clients=try XCTUnwrap(work.saved.first { $0.title == "Clients" })
        let research=try XCTUnwrap(work.saved.first { $0.title == "Research" })
        XCTAssertEqual(research.parentID,clients.id)
        XCTAssertEqual(work.saved.first { $0.title == "Saved" }?.parentID,research.id)
        XCTAssertNotNil(work.saved.first { $0.title == "Split view" })
        XCTAssertNotEqual(work.profileID,result.spaces[1].profileID)
        XCTAssertEqual(work.arcSourceID,"arc-a")
        XCTAssertEqual(result.skippedItems,2)
    }
    func testMalformedCyclesAndUnknownVersionsFailSafely() throws {
        XCTAssertThrowsError(try ArcImporter.read(Data("{}".utf8)))
        var json=try JSONSerialization.jsonObject(with:fixture()) as! [String:Any]
        var sidebar=json["sidebar"] as! [String:Any]
        var containers=sidebar["containers"] as! [[String:Any]]
        var items=containers[1]["items"] as! [Any]
        items[1]=["id":"p","childrenIds":["p"],"data":["itemContainer":[:]]]
        containers[1]["items"]=items;sidebar["containers"]=containers;json["sidebar"]=sidebar
        let result=try ArcImporter.read(JSONSerialization.data(withJSONObject:json))
        XCTAssertGreaterThan(result.skippedItems,0)
        XCTAssertEqual(result.spaces.count,2)
    }
    func testImportIsLazyAndNeverReusesArcIdentityForProfile() throws {
        let first=try ArcImporter.read(fixture()), second=try ArcImporter.read(fixture())
        XCTAssertEqual(first.spaces.map(\.arcSourceID),second.spaces.map(\.arcSourceID))
        XCTAssertNotEqual(first.spaces.map(\.profileID),second.spaces.map(\.profileID))
    }
    func testFavoritesAreCopiedByArcProfileWithoutSharingAavaStorage() throws {
        var json=try JSONSerialization.jsonObject(with:fixture()) as! [String:Any]
        var sidebar=json["sidebar"] as! [String:Any]
        var containers=sidebar["containers"] as! [[String:Any]]
        var items=containers[1]["items"] as! [Any]
        items += ["favorites",["id":"favorites","childrenIds":["fav"],"data":["itemContainer":[:]]],"fav",["id":"fav","data":["tab":["savedURL":"https://example.org/favorite","savedTitle":"Favorite"]]]]
        containers[1]["items"]=items
        containers[1]["topAppsContainerIDs"]=[["default":true],"favorites"]
        sidebar["containers"]=containers;json["sidebar"]=sidebar
        let result=try ArcImporter.read(JSONSerialization.data(withJSONObject:json))
        let a=try XCTUnwrap(result.spaces[0].saved.first { $0.title == "Favorite" })
        let b=try XCTUnwrap(result.spaces[1].saved.first { $0.title == "Favorite" })
        XCTAssertEqual(a.url,b.url);XCTAssertNotEqual(a.id,b.id);XCTAssertNotEqual(a.parentID,b.parentID)
        XCTAssertNotEqual(result.spaces[0].profileID,result.spaces[1].profileID)
    }

}
