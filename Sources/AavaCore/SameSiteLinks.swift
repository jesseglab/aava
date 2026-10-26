import Foundation

public enum SameSiteLinkChoice: String, Codable, Sendable {
    case newTab, replace
    public var title: String { self == .newTab ? "New tab" : "Replace current tab" }
}

public enum SameSiteLinks {
    // Exact hosts avoid applying preferences across unrelated subdomains.
    public static func domain(_ url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }
    public static func sharedDomain(source: URL, target: URL) -> String? {
        guard let sourceHost = domain(source), sourceHost == domain(target) else { return nil }
        return sourceHost
    }
}

public struct LinkChoiceCountdown: Equatable, Sendable {
    public private(set) var remaining: TimeInterval = 2
    public init() {}
    public mutating func advance(by elapsed: TimeInterval, paused: Bool) -> Bool {
        guard !paused, elapsed.isFinite, elapsed >= 0 else { return false }
        remaining = max(0, remaining - elapsed)
        return remaining == 0
    }
}
