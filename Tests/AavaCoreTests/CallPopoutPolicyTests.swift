import XCTest
@testable import AavaCore

final class CallPopoutPolicyTests: XCTestCase {
    func testMeetingCaptureFloatsOnTabSwitchAndDocksOnReturn() {
        let meeting = UUID(), other = UUID()
        var policy = CallPopoutPolicy()
        let urls = [meeting: URL(string: "https://meet.google.com/abc-defg-hij")!]
        policy.media(meeting, active: true)
        XCTAssertEqual(policy.reconcile(selected: meeting, urls: urls), [])
        XCTAssertEqual(policy.reconcile(selected: other, urls: urls), [.float(meeting)])
        XCTAssertEqual(policy.reconcile(selected: other, urls: urls), [])
        XCTAssertEqual(policy.reconcile(selected: meeting, urls: urls), [.dock(meeting)])
    }
    func testCameraPermissionDoesNotFloatUnrelatedSites() {
        let id = UUID(); var policy = CallPopoutPolicy(); policy.media(id, active: true)
        for url in ["https://meet.google.com.evil.test/call", "http://meet.google.com/call", "https://example.org"] {
            XCTAssertEqual(policy.reconcile(selected: nil, urls: [id: URL(string: url)!]), [])
        }
    }
    func testEndingCaptureDocksAndManualPinSupportsReceiveOnlyCalls() {
        let id = UUID(); var policy = CallPopoutPolicy()
        let urls = [id: URL(string: "https://teams.cloud.microsoft/")!]
        policy.media(id, active: true)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.float(id)])
        policy.media(id, active: false)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.dock(id)])
        policy.pin(id, enabled: true)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.float(id)])
        policy.remove(id)
        XCTAssertTrue(policy.floating.isEmpty)
        XCTAssertTrue(policy.capturing.isEmpty)
    }
    func testSitePictureInPictureSuppressesDuplicateBrowserPopout() {
        let id = UUID(); var policy = CallPopoutPolicy()
        let urls = [id: URL(string: "https://meet.google.com/test")!]
        policy.media(id, active: true)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.float(id)])
        policy.sitePopout(id, active: true)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.dock(id)])
        policy.pin(id, enabled: true)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [])
        policy.sitePopout(id, active: false)
        XCTAssertEqual(policy.reconcile(selected: id, urls: urls), [])
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.float(id)])
        policy.remove(id)
        XCTAssertTrue(policy.sitePopouts.isEmpty)
    }
    func testDisablingAutomaticPopoutsDocksExistingCall() {
        let id = UUID(); var policy = CallPopoutPolicy()
        let urls = [id: URL(string: "https://teams.microsoft.com/v2/")!]
        policy.media(id, active: true)
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.float(id)])
        policy.enabled = false
        XCTAssertEqual(policy.reconcile(selected: nil, urls: urls), [.dock(id)])
    }
}
