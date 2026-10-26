import XCTest
@testable import AavaCore

final class SameSiteLinksTests: XCTestCase {
    func testExactHostsAndSupportedSchemes() {
        func matches(_ from: String, _ to: String) -> String? { SameSiteLinks.sharedDomain(source: URL(string: from)!, target: URL(string: to)!) }
        XCTAssertEqual(matches("https://EXAMPLE.com/a", "https://example.com/b?q=1"), "example.com")
        XCTAssertEqual(matches("https://example.com./a", "https://example.com/b"), "example.com")
        XCTAssertNil(matches("https://example.com", "https://example.com.evil.test"))
        XCTAssertNil(matches("https://example.com", "https://other.example.com"))
        XCTAssertNil(matches("https://example.com", "file:///example.com"))
        XCTAssertNil(matches("https://example.com", "https://user:password@example.com"))
        XCTAssertNil(matches("https://example.com", "javascript:alert(1)"))
    }
    func testTwoSecondsAndHoverPause() {
        var countdown = LinkChoiceCountdown()
        XCTAssertFalse(countdown.advance(by: 0.75, paused: false))
        XCTAssertFalse(countdown.advance(by: 40, paused: true))
        XCTAssertEqual(countdown.remaining, 1.25)
        XCTAssertFalse(countdown.advance(by: 1, paused: false))
        XCTAssertTrue(countdown.advance(by: 0.25, paused: false))
        XCTAssertEqual(countdown.remaining, 0)
    }
    func testInvalidTimingCannotCompleteCountdown() {
        var countdown = LinkChoiceCountdown()
        XCTAssertFalse(countdown.advance(by: -.infinity, paused: false))
        XCTAssertFalse(countdown.advance(by: .nan, paused: false))
        XCTAssertFalse(countdown.advance(by: -2, paused: false))
        XCTAssertEqual(countdown.remaining, 2)
    }
    func testPreferencePersistenceIsolationAndOldSessions() throws {
        var state = BrowserState()
        state.spaces[0].sameSiteLinkChoices = ["example.com": .replace]
        let decoded = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.spaces[0].sameSiteLinkChoices?["example.com"], .replace)
        XCTAssertNil(decoded.spaces[1].sameSiteLinkChoices)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state.spaces[0])) as? [String: Any])
        object.removeValue(forKey: "sameSiteLinkChoices")
        let old = try JSONDecoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.sameSiteLinkChoices)
    }
}
