import Foundation
import Security

struct PrivateSpaceVault {
    struct Record: Codable { var verifier: PINVerifier; var attempts = PINAttemptPolicy() }
    enum Failure: LocalizedError {
        case missing, keychain(OSStatus), wrong(Int)
        var errorDescription: String? {
            switch self {
            case .missing: return "This space’s PIN record is unavailable. The space remains locked."
            case .keychain: return "Aava couldn’t access the PIN in your Mac Keychain. The space remains locked."
            case .wrong(let seconds): return seconds > 0 ? "Try again in \(seconds) seconds." : "That PIN didn’t match."
            }
        }
    }
    private let service: String
    init(service: String = (Bundle.main.bundleIdentifier ?? "app.geeklab.aava.dev") + ".private-space-pin") { self.service = service }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:id.uuidString]
    }
    func create(_ id: UUID, pin: String) throws {
        let record = Record(verifier:try PINVerifier(pin:pin))
        var attributes = query(id)
        attributes[kSecValueData as String] = try JSONEncoder().encode(record)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary,nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
    func replace(_ id: UUID, pin: String) throws {
        let data = try JSONEncoder().encode(Record(verifier: try PINVerifier(pin: pin)))
        let result = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound { try create(id, pin: pin) }
        else if result != errSecSuccess { throw Failure.keychain(result) }
    }
    func removeNewRecord(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
    }
    func verify(_ id: UUID, pin: String, now: Date = Date()) throws {
        var attributes = query(id); attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary,&value)
        guard status == errSecSuccess, let data = value as? Data else { throw status == errSecItemNotFound ? Failure.missing : Failure.keychain(status) }
        var record = try JSONDecoder().decode(Record.self,from:data)
        let wait = record.attempts.wait(now:now)
        guard wait == 0 else { throw Failure.wrong(wait) }
        let valid = try record.verifier.matches(pin)
        if valid { record.attempts.succeeded() } else { record.attempts.failed(now:now) }
        let update = [kSecValueData as String:try JSONEncoder().encode(record)]
        let saved = SecItemUpdate(query(id) as CFDictionary,update as CFDictionary)
        guard saved == errSecSuccess else { throw Failure.keychain(saved) }
        if !valid { throw Failure.wrong(record.attempts.wait(now:now)) }
    }
}
