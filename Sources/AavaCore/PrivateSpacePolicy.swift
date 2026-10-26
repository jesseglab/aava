import Foundation

public struct PrivateSpaceSettings: Codable, Equatable, Sendable {
    public var idleMinutes: Int
    public var stayOn: Bool?
    public init(idleMinutes: Int = 15, stayOn: Bool = false) { self.idleMinutes = [15, 30, 60].contains(idleMinutes) ? idleMinutes : 15; self.stayOn = stayOn }
}

/// Unlock grants live only in memory. Neither an app restart nor decoded session grants access.
public struct PrivateSpacePolicy {
    public struct Grant: Equatable {
        public var stayOn: Bool
        public var idleSeconds: TimeInterval
        public var lastActivity: Date
    }
    public private(set) var grants: [UUID: Grant] = [:]
    public init() {}
    public func isUnlocked(_ id: UUID, now: Date) -> Bool {
        guard let grant = grants[id] else { return false }
        let elapsed = now.timeIntervalSince(grant.lastActivity)
        return elapsed >= 0 && elapsed < grant.idleSeconds
    }
    public mutating func unlock(_ id: UUID, stayOn: Bool, minutes: Int, now: Date) {
        grants[id] = Grant(stayOn: stayOn, idleSeconds: TimeInterval([15,30,60].contains(minutes) ? minutes * 60 : 900), lastActivity: now)
    }
    public mutating func leave(_ id: UUID) { if grants[id]?.stayOn != true { grants.removeValue(forKey: id) } }
    public mutating func activity(in id: UUID, now: Date) {
        guard isUnlocked(id, now: now) else { return }
        grants[id]?.lastActivity = now
    }
    @discardableResult public mutating func expire(now: Date) -> Set<UUID> {
        let expired = Set(grants.keys.filter { !isUnlocked($0, now: now) })
        expired.forEach { grants.removeValue(forKey: $0) }
        return expired
    }
    public mutating func lock(_ id: UUID) { grants.removeValue(forKey: id) }
    public mutating func lockAll() { grants.removeAll() }
}
