import Foundation
import SQLite3
import CryptoKit
import CommonCrypto

public struct ArcExtensionInfo: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var storeURL: URL? { Self.validID(id) ? URL(string: "https://chromewebstore.google.com/detail/" + id) : nil }
    public static func validID(_ id: String) -> Bool { id.count == 32 && id.utf8.allSatisfy { (97...112).contains($0) } }
}
public struct ArcProfileSummary: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var historyCount: Int?
    public var cookieCount: Int?
    public var bookmarks: [SavedItem]
    public var extensions: [ArcExtensionInfo]
    public var notes: [String]
}
public struct ArcSessionCookie: Codable, Sendable {
    public var host: String, name: String, value: String, path: String
    public var secure: Bool, httpOnly: Bool, persistent: Bool
    public var expires: String
    public var sameSite: Int
}
public enum ArcProfileImport {
    public enum Failure: LocalizedError {
        case invalidPath, unreadable, databaseBusy, encryption, unsupported
        public var errorDescription: String? {
            switch self {
            case .invalidPath: return "Choose Arc’s User Data folder and a profile inside it."
            case .unreadable: return "This Arc data could not be read. Arc has not been changed."
            case .databaseBusy: return "Arc’s database is busy. Quit Arc, then try again."
            case .encryption: return "Arc’s encrypted session data could not be unlocked. Sign in again or try after unlocking your Mac Keychain."
            case .unsupported: return "This cookie format is newer than this importer supports. Other selected data can still be imported."
            }
        }
    }
    public static func profileURL(root: URL, directory: String) throws -> URL {
        guard directory == "Default" || directory.range(of: "^Profile [0-9]+$", options: .regularExpression) != nil else { throw Failure.invalidPath }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = base.appendingPathComponent(directory).resolvingSymlinksInPath()
        guard result.deletingLastPathComponent() == base else { throw Failure.invalidPath }
        return result
    }
    public static func file(_ relative: String, in profile: URL) throws -> URL {
        let base = profile.resolvingSymlinksInPath()
        let file = base.appendingPathComponent(relative).resolvingSymlinksInPath()
        guard file.path.hasPrefix(base.path + "/") else { throw Failure.invalidPath }
        return file
    }
    static func json(_ url: URL, limit: Int = 32 * 1024 * 1024) throws -> [String: Any] {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= limit else { throw Failure.unreadable }
        guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw Failure.unreadable }
        return value
    }
    public static func scan(root: URL) throws -> [ArcProfileSummary] {
        let directories = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 == "Default" || $0.range(of: "^Profile [0-9]+$", options: .regularExpression) != nil }.sorted()
        let names = ((try? json(root.appendingPathComponent("Local State")))?["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] ?? [:]
        return try directories.map { directory in
            let path = try profileURL(root: root, directory: directory)
            var notes: [String] = []
            func count(_ file: String, _ table: String) -> Int? {
                guard FileManager.default.fileExists(atPath: path.appendingPathComponent(file).path) else { return 0 }
                do { return try database(try Self.file(file, in: path)) { db in Int(try scalar(db, "SELECT count(*) FROM " + table)) } }
                catch { notes.append(file + " is busy or unavailable. Quit Arc to read it."); return nil }
            }
            var bookmarks: [SavedItem] = []
            if FileManager.default.fileExists(atPath: path.appendingPathComponent("Bookmarks").path) {
                do { bookmarks = try readBookmarks(try file("Bookmarks", in: path)) }
                catch { notes.append("Bookmarks could not be read.") }
            }
            let cookies = FileManager.default.fileExists(atPath: path.appendingPathComponent("Network/Cookies").path) ? "Network/Cookies" : "Cookies"
            return ArcProfileSummary(id: directory, name: names[directory]?["name"] as? String ?? directory,
                historyCount: count("History", "urls"), cookieCount: count(cookies, "cookies"), bookmarks: bookmarks,
                extensions: (try? extensions(path)) ?? [], notes: notes)
        }
    }
    public static func readBookmarks(_ file: URL) throws -> [SavedItem] {
        let roots = try json(file)["roots"] as? [String: [String: Any]] ?? [:]
        var result: [SavedItem] = []
        func walk(_ node: [String: Any], parent: UUID?, depth: Int) {
            guard depth < 64, result.count < 20_000 else { return }
            let title = String((node["name"] as? String ?? "Imported").prefix(300))
            if node["type"] as? String == "url", let string = node["url"] as? String, let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                result.append(SavedItem(title: title, url: url, parentID: parent))
            } else if let children = node["children"] as? [[String: Any]] {
                let folder = SavedItem(title: title, parentID: parent); result.append(folder)
                children.forEach { walk($0, parent: folder.id, depth: depth + 1) }
            }
        }
        for key in roots.keys.sorted() { if let root = roots[key] { walk(root, parent: nil, depth: 0) } }
        return result
    }
    public static func extensions(_ profile: URL) throws -> [ArcExtensionInfo] {
        let base = try file("Extensions", in: profile)
        guard FileManager.default.fileExists(atPath: base.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: base.path).filter(ArcExtensionInfo.validID).sorted().compactMap { id in
            let versions = try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(id).path).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for version in versions {
                let manifest = base.appendingPathComponent(id).appendingPathComponent(version).appendingPathComponent("manifest.json").resolvingSymlinksInPath()
                guard manifest.path.hasPrefix(base.resolvingSymlinksInPath().path + "/"), let data = try? json(manifest, limit: 2 * 1024 * 1024) else { continue }
                var name = data["name"] as? String ?? id
                if name.hasPrefix("__MSG_"), name.hasSuffix("__"), let locale = data["default_locale"] as? String,
                   locale.range(of: "^[A-Za-z_]+$", options: .regularExpression) != nil {
                    let messages = manifest.deletingLastPathComponent().appendingPathComponent("_locales/" + locale + "/messages.json").resolvingSymlinksInPath()
                    if messages.path.hasPrefix(base.path + "/"), let localized = try? json(messages, limit: 2 * 1024 * 1024),
                       let message = localized[String(name.dropFirst(6).dropLast(2))] as? [String: Any], let title = message["message"] as? String { name = title }
                }
                return ArcExtensionInfo(id: id, name: name.hasPrefix("__MSG_") ? id : String(name.prefix(200)), version: data["version"] as? String ?? version)
            }
            return nil
        }
    }
    public static func history(_ file: URL) throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try database(file) { db in
            var result: [HistoryEntry] = []
            try rows(db, "SELECT url,title,last_visit_time,visit_count FROM urls ORDER BY last_visit_time DESC LIMIT 10000") { row in
                guard let url = URL(string: text(row, 0)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return }
                result.append(HistoryEntry(url: url, title: String(text(row, 1).prefix(500)), visitedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(row, 2)) / 1_000_000 - 11_644_473_600), visits: max(1, Int(sqlite3_column_int64(row, 3)))))
            }
            return result
        }
    }
    public static func cookies(_ file: URL, password: Data, now: Date = Date()) throws -> (items: [ArcSessionCookie], skipped: Int) {
        try database(file) { db in
            let version = try scalar(db, "SELECT value FROM meta WHERE key='version'")
            guard version <= 24 else { throw Failure.unsupported }
            let key = try derivedKey(password)
            var result: [ArcSessionCookie] = [], skipped = max(0, Int(try scalar(db, "SELECT count(*) FROM cookies")) - 20000)
            let columns = try columnNames(db, "cookies")
            let partition = columns.contains("top_frame_site_key") ? "top_frame_site_key" : "''"
            try rows(db, "SELECT host_key,name,value,encrypted_value,path,expires_utc,is_secure,is_httponly,is_persistent,samesite," + partition + " FROM cookies LIMIT 20000") { row in
                let expires = sqlite3_column_int64(row, 5), persistent = sqlite3_column_int(row, 8) != 0
                guard text(row, 10).isEmpty, !persistent || Double(expires) / 1_000_000 - 11_644_473_600 > now.timeIntervalSince1970 else { skipped += 1; return }
                let host = text(row, 0), encrypted = bytes(row, 3)
                let value: String
                if encrypted.isEmpty { value = text(row, 2) }
                else {
                    guard let decoded = try? decrypt(encrypted, key: key, host: host, hashedHost: version >= 24) else { skipped += 1; return }
                    value = decoded
                }
                guard !host.isEmpty, !host.contains("/"), !host.contains(":") else { skipped += 1; return }
                result.append(ArcSessionCookie(host: host, name: text(row, 1), value: value, path: text(row, 4), secure: sqlite3_column_int(row, 6) != 0, httpOnly: sqlite3_column_int(row, 7) != 0, persistent: persistent, expires: String(expires), sameSite: Int(sqlite3_column_int(row, 9))))
            }
            return (result, skipped)
        }
    }
    public static func derivedKey(_ password: Data) throws -> Data {
        var key = Data(count: 16)
        let salt = Array("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { output in password.withUnsafeBytes { input in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), input.bindMemory(to: Int8.self).baseAddress, password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, output.bindMemory(to: UInt8.self).baseAddress, 16)
        } }
        guard status == kCCSuccess else { throw Failure.encryption }; return key
    }
    public static func decrypt(_ data: Data, key: Data, host: String, hashedHost: Bool) throws -> String {
        guard data.prefix(3) == Data("v10".utf8), key.count == 16 else { throw Failure.unsupported }
        let ciphertext = data.dropFirst(3), iv = [UInt8](repeating: 32, count: 16)
        var output = Data(count: ciphertext.count + 16), written = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { out in key.withUnsafeBytes { keyBytes in ciphertext.withUnsafeBytes { input in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, key.count, iv, input.baseAddress, ciphertext.count, out.baseAddress, capacity, &written)
        } } }
        guard status == kCCSuccess else { throw Failure.encryption }
        output.count = written
        if hashedHost {
            let hash = Data(SHA256.hash(data: Data(host.utf8)))
            guard output.starts(with: hash) else { throw Failure.encryption }; output.removeFirst(32)
        }
        guard let value = String(data: output, encoding: .utf8) else { throw Failure.encryption }; return value
    }
    static func database<T>(_ file: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }; throw Failure.unreadable
        }
        defer { sqlite3_close(db) }; sqlite3_busy_timeout(db, 500)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw Failure.databaseBusy }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        return try body(db)
    }
    static func rows(_ db: OpaquePointer, _ sql: String, _ visit: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure.unreadable }
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { try visit(statement); status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw status == SQLITE_BUSY || status == SQLITE_LOCKED ? Failure.databaseBusy : Failure.unreadable }
    }
    static func scalar(_ db: OpaquePointer, _ sql: String) throws -> Int64 { var n: Int64 = 0; try rows(db, sql) { n = sqlite3_column_int64($0, 0) }; return n }
    static func columnNames(_ db: OpaquePointer, _ table: String) throws -> Set<String> { var names = Set<String>(); try rows(db, "PRAGMA table_info(" + table + ")") { names.insert(text($0, 1)) }; return names }
    static func text(_ row: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(row, column).map { String(cString: $0) } ?? "" }
    static func bytes(_ row: OpaquePointer, _ column: Int32) -> Data { guard let p = sqlite3_column_blob(row, column) else { return Data() }; return Data(bytes: p, count: Int(sqlite3_column_bytes(row, column))) }
}
