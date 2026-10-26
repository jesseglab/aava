import XCTest
import SQLite3
import CommonCrypto
import CryptoKit
@testable import AavaCore

final class ArcProfileImportTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aava-arc-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Default"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func write(_ object: Any, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
    func sql(_ path: String, _ sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent(path).path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
    func encrypted(_ value: String, host: String, version: Int = 24) throws -> Data {
        let key = try ArcProfileImport.derivedKey(Data("synthetic-test-only".utf8))
        var plaintext = version >= 24 ? Data(SHA256.hash(data: Data(host.utf8))) : Data()
        plaintext.append(Data(value.utf8))
        let iv = [UInt8](repeating: 32, count: 16)
        var result = Data(count: plaintext.count + 16), written = 0
        let size = result.count
        let status = result.withUnsafeMutableBytes { out in key.withUnsafeBytes { k in plaintext.withUnsafeBytes { input in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, 16, iv, input.baseAddress, plaintext.count, out.baseAddress, size, &written)
        } } }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess)); result.count = written
        return Data("v10".utf8) + result
    }
    func cookieDatabase(version: Int = 24) throws {
        try sql("Default/Cookies", """
        CREATE TABLE meta (key TEXT, value TEXT); INSERT INTO meta VALUES ('version','\(version)');
        CREATE TABLE cookies (host_key TEXT,name TEXT,value TEXT,encrypted_value BLOB,path TEXT,expires_utc INTEGER,is_secure INTEGER,is_httponly INTEGER,is_persistent INTEGER,samesite INTEGER,top_frame_site_key TEXT);
        """)
    }
    func testScanProfilesBookmarksAndLocalizedExtensionInventory() throws {
        try write(["profile": ["info_cache": ["Default": ["name": "Synthetic Work"]]]], "Local State")
        try write(["roots": ["bookmark_bar": ["type": "folder", "name": "Imported bookmarks", "children": [
            ["type": "folder", "name": "Research", "children": [["type": "url", "name": "Example", "url": "https://example.test"]]],
            ["type": "url", "name": "Rejected", "url": "javascript:alert(1)"]
        ]]]], "Default/Bookmarks")
        let id = String(repeating: "a", count: 32)
        try write(["name": "__MSG_appName__", "version": "2.0", "default_locale": "en"], "Default/Extensions/\(id)/2.0/manifest.json")
        try write(["appName": ["message": "Fixture Extension"]], "Default/Extensions/\(id)/2.0/_locales/en/messages.json")
        let profiles = try ArcProfileImport.scan(root: root)
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profiles.count, 1); XCTAssertEqual(profile.name, "Synthetic Work")
        XCTAssertEqual(profile.bookmarks.count, 3)
        XCTAssertEqual(profile.bookmarks[2].parentID, profile.bookmarks[1].id)
        XCTAssertEqual(profile.extensions.first?.name, "Fixture Extension")
        XCTAssertEqual(profile.extensions.first?.storeURL?.host, "chromewebstore.google.com")
        XCTAssertEqual(profile.cookieCount, 0)
    }
    func testPathTraversalAndSymlinkEscapesRejected() throws {
        XCTAssertThrowsError(try ArcProfileImport.profileURL(root: root, directory: "../Default"))
        let outside = root.deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Profile 1"), withDestinationURL: outside)
        XCTAssertThrowsError(try ArcProfileImport.profileURL(root: root, directory: "Profile 1"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Default/History"), withDestinationURL: outside)
        XCTAssertThrowsError(try ArcProfileImport.file("History", in: root.appendingPathComponent("Default")))
        XCTAssertFalse(ArcExtensionInfo.validID(String(repeating: "q", count: 32)))
        XCTAssertFalse(ArcExtensionInfo.validID("../../secrets"))
    }
    func testHistoryUsesChromiumEpochAndRejectsInternalURLs() throws {
        try sql("Default/History", """
        CREATE TABLE urls (url TEXT,title TEXT,last_visit_time INTEGER,visit_count INTEGER);
        INSERT INTO urls VALUES ('https://example.test','Fixture',11644473642000000,3);
        INSERT INTO urls VALUES ('chrome://settings','Internal',11644473643000000,1);
        """)
        let history = try ArcProfileImport.history(root.appendingPathComponent("Default/History"))
        XCTAssertEqual(history.count, 1); XCTAssertEqual(history.first?.visitedAt.timeIntervalSince1970, 42)
        XCTAssertEqual(history.first?.visits, 3)
    }
    func testCookieDecryptionChecksHostBindingAndWrongKey() throws {
        let cipher = try encrypted("synthetic-token", host: ".example.test")
        let key = try ArcProfileImport.derivedKey(Data("synthetic-test-only".utf8))
        XCTAssertEqual(try ArcProfileImport.decrypt(cipher, key: key, host: ".example.test", hashedHost: true), "synthetic-token")
        XCTAssertThrowsError(try ArcProfileImport.decrypt(cipher, key: key, host: ".other.test", hashedHost: true))
        XCTAssertThrowsError(try ArcProfileImport.decrypt(cipher, key: Data(repeating: 0, count: 16), host: ".example.test", hashedHost: true))
        XCTAssertThrowsError(try ArcProfileImport.decrypt(Data("v20".utf8) + cipher.dropFirst(3), key: key, host: ".example.test", hashedHost: true))
        let legacy = try encrypted("legacy-value", host: ".example.test", version: 23)
        XCTAssertEqual(try ArcProfileImport.decrypt(legacy, key: key, host: ".example.test", hashedHost: false), "legacy-value")
    }
    func testCookieTransferFiltersExpiredPartitionedAndUndecryptable() throws {
        try cookieDatabase()
        let cipher = try encrypted("synthetic-token", host: ".example.test").map { String(format: "%02x", $0) }.joined()
        try sql("Default/Cookies", """
        INSERT INTO cookies VALUES ('.example.test','session','',X'\(cipher)','/',0,1,1,0,2,'');
        INSERT INTO cookies VALUES ('example.test','expired','gone',X'','/',1,0,0,1,1,'');
        INSERT INTO cookies VALUES ('example.test','partitioned','skip',X'','/',0,1,0,0,0,'https://other.test');
        INSERT INTO cookies VALUES ('example.test','unknown','',X'7632300000','/',0,1,0,0,0,'');
        """)
        let before = try Data(contentsOf: root.appendingPathComponent("Default/Cookies"))
        let result = try ArcProfileImport.cookies(root.appendingPathComponent("Default/Cookies"), password: Data("synthetic-test-only".utf8))
        XCTAssertEqual(result.items.count, 1); XCTAssertEqual(result.skipped, 3)
        let cookie = try XCTUnwrap(result.items.first)
        XCTAssertTrue(cookie.secure); XCTAssertTrue(cookie.httpOnly); XCTAssertFalse(cookie.persistent)
        XCTAssertEqual(cookie.sameSite, 2); XCTAssertEqual(cookie.value, "synthetic-token")
        XCTAssertEqual(before, try Data(contentsOf: root.appendingPathComponent("Default/Cookies")))
    }
    func testFutureCookieSchemaFailsClosed() throws {
        try cookieDatabase(version: 25)
        XCTAssertThrowsError(try ArcProfileImport.cookies(root.appendingPathComponent("Default/Cookies"), password: Data("unused".utf8)))
    }
    func testImportedExtensionListPersistsWithSpace() throws {
        var space = BrowserSpace(name: "Fixture", emoji: "A", theme: .tide)
        space.arcExtensions = [ArcExtensionInfo(id: String(repeating: "b", count: 32), name: "Fixture", version: "1")]
        space.arcProfileDirectory = "Profile 2"
        let restored = try JSONDecoder().decode(BrowserSpace.self, from: JSONEncoder().encode(space))
        XCTAssertEqual(space, restored)
        XCTAssertNotEqual(space.profileID, BrowserSpace(name: "Other", emoji: "B", theme: .tide).profileID)
    }
}
