import XCTest
@testable import AavaCore

final class MiniGuideTests: XCTestCase {
    func testInactiveGuideDoesNotInventAConnection() {
        let prompt = AavaMiniGuide.prompt(cli: "/tmp/client", connection: nil)
        XCTAssertFalse(prompt.contains("--connection"))
        XCTAssertTrue(prompt.contains("Start Mini"))
    }
    func testShellQuotingHandlesSpacesQuotesAndSubstitutions() {
        XCTAssertEqual(AavaMiniGuide.shellQuote("/Aava's app/$(touch x)"), "'/Aava'\"'\"'s app/$(touch x)'")
    }
    func testSessionSpecificGuideAndCompletedOnboardingStayOptional() {
        let prompt = AavaMiniGuide.prompt(cli: "/Applications/Aava Preview.app/client", connection: "/tmp/session A/connection.json")
        XCTAssertTrue(prompt.contains("--connection '/tmp/session A/connection.json'"))
        var state = OnboardingState()
        state.completedVersion = 1
        XCTAssertFalse(state.needsPresentation)
        state.step = 5
        state.normalize()
        XCTAssertEqual(state.step, 5)
    }
}
