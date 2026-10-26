import Foundation
import CommonCrypto
import Security

public struct PINVerifier: Codable, Equatable {
    public var salt: Data
    public var digest: Data
    public var rounds: UInt32
    public init(pin: String) throws {
        guard Self.isValid(pin) else { throw PINError.invalid }
        var bytes = [UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PINError.crypto }
        salt = Data(bytes); rounds = 600_000
        digest = try Self.derive(pin:pin,salt:salt,rounds:rounds)
    }
    public static func isValid(_ pin: String) -> Bool { (6...12).contains(pin.utf8.count) && pin.utf8.allSatisfy { (48...57).contains($0) } }
    public func matches(_ pin: String) throws -> Bool {
        guard Self.isValid(pin), salt.count == 32, digest.count == 32, (100_000...2_000_000).contains(rounds) else { return false }
        let candidate = try Self.derive(pin:pin,salt:salt,rounds:rounds)
        return zip(candidate,digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func derive(pin: String, salt: Data, rounds: UInt32) throws -> Data {
        var result = [UInt8](repeating:0,count:32)
        let status = pin.withCString { password in salt.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, pin.utf8.count, bytes.bindMemory(to:UInt8.self).baseAddress!, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &result, result.count)
        } }
        guard status == kCCSuccess else { throw PINError.crypto }
        return Data(result)
    }
    public enum PINError: LocalizedError {
        case invalid, crypto
        public var errorDescription: String? { self == .invalid ? "Use a PIN with 6–12 digits." : "The PIN could not be secured. Please try again." }
    }
}

public struct PINAttemptPolicy: Codable {
    public var failures = 0
    public var retryAfter: Date?
    public init() {}
    public func wait(now: Date) -> Int { max(0,Int(ceil((retryAfter ?? now).timeIntervalSince(now)))) }
    public mutating func failed(now: Date) {
        failures = min(failures + 1, 20)
        if failures >= 5 { retryAfter = now.addingTimeInterval(min(900,30 * pow(2,Double(failures-5)))) }
    }
    public mutating func succeeded() { failures = 0; retryAfter = nil }
}
