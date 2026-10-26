import XCTest
@testable import AavaCore

final class NotificationTests: XCTestCase {
    func testDefaultsAndForwardCompatibleSettings() throws {
        let decoder = JSONDecoder()
        for json in ["{}", "{\"position\":\"future-position\"}"] {
            let value = try decoder.decode(NotificationPreferences.self, from: Data(json.utf8))
            XCTAssertEqual(value.position, .topRight)
            XCTAssertFalse(value.expanded)
        }
        XCTAssertEqual(ToastPosition.allCases.count, 6)
    }
    func testEveryPositionAndExpansionSurvivesRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = NotificationPreferencesRepository(fileURL: root.appendingPathComponent("notifications.json"))
        XCTAssertEqual(try repository.load(), NotificationPreferences())
        for position in ToastPosition.allCases {
            for expanded in [true, false] {
                var settings = NotificationPreferences(); settings.position = position; settings.expanded = expanded
                try repository.save(settings)
                XCTAssertEqual(try repository.load(), settings)
            }
        }
    }
    func testBoundedQueueCoalescesAndClearsPrivateContent() {
        var queue = ToastQueue(); let scope = UUID()
        for i in 0..<10 { queue.push(AavaToast(title: "Saved \(i)", scope: scope)) }
        XCTAssertEqual(queue.items.count, 3)
        queue.push(AavaToast(title: "Saved 9", scope: scope))
        XCTAssertEqual(queue.items.count, 3)
        XCTAssertEqual(queue.items.filter { $0.title == "Saved 9" }.count, 1)
        let staleID = queue.items[0].id
        queue.push(AavaToast(title: "Saved 9", scope: scope))
        queue.remove(staleID)
        XCTAssertEqual(queue.items.first?.title, "Saved 9")
        queue.clear()
        XCTAssertTrue(queue.items.isEmpty)
    }
}
