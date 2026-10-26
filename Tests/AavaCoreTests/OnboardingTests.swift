import XCTest
@testable import AavaCore

final class OnboardingTests: XCTestCase {
    func testFirstRunResumeCompletionAndReplay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = OnboardingRepository(fileURL: directory.appendingPathComponent("onboarding.json"))
        var welcome = try repository.load()
        XCTAssertTrue(welcome.needsPresentation)
        welcome.advance(); welcome.advance()
        try repository.save(welcome)
        XCTAssertEqual(try repository.load().step, 2)
        welcome.complete()
        try repository.save(welcome)
        var restored = try repository.load()
        XCTAssertFalse(restored.needsPresentation)
        restored.replay()
        XCTAssertEqual(restored.step, 0)
        XCTAssertFalse(restored.needsPresentation, "Replay must not force onboarding again on the next launch")
    }
    func testStepBoundsAndFutureVersion() throws {
        var state = OnboardingState()
        for _ in 0..<8 { state.advance() }
        XCTAssertEqual(state.step, 6)
        for _ in 0..<8 { state.back() }
        XCTAssertEqual(state.step, 0)
        state.step = -100; state.normalize(); XCTAssertEqual(state.step, 0)
        state.step = 100; state.normalize(); XCTAssertEqual(state.step, 6)
        state.completedVersion = 99
        XCTAssertFalse(state.needsPresentation, "An older app must not re-onboard a newer completed profile")
    }
}
