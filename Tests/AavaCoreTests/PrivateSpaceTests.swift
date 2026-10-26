import XCTest
@testable import AavaCore

final class PrivateSpaceTests: XCTestCase {
    func testLeaveLocksUnlessStayOnAndIdleIsPerSpace() {
        let a=UUID(), b=UUID(), start=Date(timeIntervalSince1970:1000)
        var policy=PrivateSpacePolicy()
        XCTAssertFalse(policy.isUnlocked(a,now:start))
        policy.unlock(a,stayOn:false,minutes:15,now:start);policy.leave(a)
        XCTAssertFalse(policy.isUnlocked(a,now:start))
        policy.unlock(a,stayOn:true,minutes:15,now:start);policy.leave(a)
        XCTAssertTrue(policy.isUnlocked(a,now:start.addingTimeInterval(899)))
        policy.activity(in:b,now:start.addingTimeInterval(899))
        XCTAssertEqual(policy.expire(now:start.addingTimeInterval(900)),[a])
    }
    func testAllTimeoutsAndActivityDoesNotResurrectExpiredGrant() {
        for minutes in [15,30,60] {
            let id=UUID(), start=Date(timeIntervalSince1970:1000)
            var policy=PrivateSpacePolicy()
            policy.unlock(id,stayOn:true,minutes:minutes,now:start)
            policy.activity(in:id,now:start.addingTimeInterval(30))
            XCTAssertTrue(policy.isUnlocked(id,now:start.addingTimeInterval(Double(minutes*60)+29)))
            policy.activity(in:id,now:start.addingTimeInterval(Double(minutes*60)+30))
            XCTAssertFalse(policy.isUnlocked(id,now:start.addingTimeInterval(Double(minutes*60)+30)))
            policy.lockAll(); XCTAssertTrue(policy.grants.isEmpty)
        }
    }
    func testClockRollbackFailsClosedAndRestartHasNoGrant() {
        let id=UUID(), now=Date();var policy=PrivateSpacePolicy()
        policy.unlock(id,stayOn:true,minutes:15,now:now)
        XCTAssertFalse(policy.isUnlocked(id,now:now.addingTimeInterval(-1)))
        XCTAssertFalse(PrivateSpacePolicy().isUnlocked(id,now:now))
    }
    func testPINVerificationAndSalt() throws {
        let a=try PINVerifier(pin:"583926"), b=try PINVerifier(pin:"583926")
        XCTAssertNotEqual(a.salt,b.salt);XCTAssertNotEqual(a.digest,b.digest)
        XCTAssertTrue(try a.matches("583926"));XCTAssertFalse(try a.matches("583927"))
        XCTAssertFalse(try a.matches("１２３４５６"));XCTAssertThrowsError(try PINVerifier(pin:"123"))
        let encoded=try JSONEncoder().encode(a)
        XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("583926"))
        XCTAssertTrue(try JSONDecoder().decode(PINVerifier.self,from:encoded).matches("583926"))
    }
    func testPersistentAttemptBackoff() throws {
        var policy=PINAttemptPolicy();let now=Date()
        for _ in 0..<5 { policy.failed(now:now) }
        let restored=try JSONDecoder().decode(PINAttemptPolicy.self,from:JSONEncoder().encode(policy))
        XCTAssertEqual(restored.wait(now:now),30)
        XCTAssertEqual(restored.wait(now:now.addingTimeInterval(30)),0)
        policy.failed(now:now.addingTimeInterval(30));XCTAssertEqual(policy.wait(now:now.addingTimeInterval(30)),60)
        policy.succeeded();XCTAssertEqual(policy.failures,0)
    }
    func testOldSessionsDecodeAndProfilesCannotBeShared() throws {
        var state=BrowserState();state.spaces[1].profileID=state.spaces[0].profileID
        state.spaces[0].privacy=PrivateSpaceSettings(idleMinutes:60)
        state.normalize()
        XCTAssertEqual(Set(state.spaces.map(\.profileID)).count,state.spaces.count)
        let data=try JSONEncoder().encode(state)
        let restored=try JSONDecoder().decode(BrowserState.self,from:data)
        XCTAssertEqual(restored.spaces[0].privacy?.idleMinutes,60)
        XCTAssertNil(restored.spaces[1].privacy)
    }
}
