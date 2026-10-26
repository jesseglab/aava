import XCTest
@testable import AavaCore

final class SpaceMaterialTests: XCTestCase {
    func testLegacySessionKeepsSolidAppearance() throws {
        let original = BrowserState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var spaces = try XCTUnwrap(json["spaces"] as? [[String: Any]])
        for index in spaces.indices { spaces[index].removeValue(forKey: "liquidGlass") }
        json["spaces"] = spaces
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(restored.currentSpace.usesLiquidGlass)
        XCTAssertEqual(restored.currentSpace.saved, original.currentSpace.saved)
    }
    func testMaterialPersistsPerSpaceIndependentlyOfPalette() throws {
        var state = BrowserState()
        state.spaces[0].liquidGlass = true
        state.spaces[0].theme = .dusk
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(restored.spaces[0].usesLiquidGlass)
        XCTAssertFalse(restored.spaces[1].usesLiquidGlass)
        XCTAssertEqual(restored.spaces[0].theme, .dusk)
    }
}
