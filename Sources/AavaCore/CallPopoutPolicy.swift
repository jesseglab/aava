import Foundation

/// Transient call state; never persisted as a live call across a restart.
public struct CallPopoutPolicy {
    public enum Transition: Equatable { case float(UUID), dock(UUID) }
    public var enabled = true
    public private(set) var capturing: Set<UUID> = []
    public private(set) var manual: Set<UUID> = []
    public private(set) var floating: Set<UUID> = []
    public private(set) var sitePopouts: Set<UUID> = []
    public init() {}
    public mutating func sitePopout(_ id: UUID, active: Bool) {
        if active { sitePopouts.insert(id) } else { sitePopouts.remove(id) }
    }
    public static func isMeeting(_ url: URL?) -> Bool {
        guard url?.scheme == "https", let host = url?.host?.lowercased() else { return false }
        return ["meet.google.com", "teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"].contains(host)
    }
    public mutating func media(_ id: UUID, active: Bool) {
        if active { capturing.insert(id) } else { capturing.remove(id) }
    }
    public mutating func pin(_ id: UUID, enabled: Bool) {
        if enabled { manual.insert(id) } else { manual.remove(id) }
    }
    public mutating func remove(_ id: UUID) {
        capturing.remove(id); manual.remove(id); floating.remove(id); sitePopouts.remove(id)
    }
    public mutating func reconcile(selected: UUID?, urls: [UUID: URL]) -> [Transition] {
        let desired = Set(urls.keys.filter { id in
            id != selected && !sitePopouts.contains(id) && (manual.contains(id) || (enabled && capturing.contains(id) && Self.isMeeting(urls[id])))
        })
        let result = floating.subtracting(desired).map { Transition.dock($0) } + desired.subtracting(floating).map { Transition.float($0) }
        floating = desired
        return result
    }
}
