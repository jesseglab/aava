import Foundation

public enum ArchiveReason: String, Codable, Sendable { case closed, automatic, clean }
public enum AutoArchiveInterval: Int, Codable, CaseIterable, Sendable {
    case off = 0, twelveHours = 12, oneDay = 24, oneWeek = 168, oneMonth = 720
    public var title: String {
        switch self { case .off: return "Off"; case .twelveHours: return "12 hours"; case .oneDay: return "24 hours"; case .oneWeek: return "7 days"; case .oneMonth: return "30 days" }
    }
}
public struct ArchivedTab: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var tab: BrowserTab
    public var closedAt: Date
    public var reason: ArchiveReason
    public init(tab: BrowserTab, closedAt: Date = Date(), reason: ArchiveReason) { self.tab = tab; self.closedAt = closedAt; self.reason = reason }
}
public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var url: URL
    public var title: String
    public var visitedAt: Date
    public var visits: Int
    public init(url: URL, title: String, visitedAt: Date = Date(), visits: Int = 1) { self.url = url; self.title = title; self.visitedAt = visitedAt; self.visits = visits }
}
public enum TabCleanup {
    public static func expired(in space: BrowserSpace, now: Date, protected: Set<UUID> = []) -> [UUID] {
        let hours = space.autoArchiveHours ?? 0
        guard hours > 0 else { return [] }
        return space.tabs.filter { tab in
            !tab.pinned && tab.id != space.selectedTabID && !protected.contains(tab.id) &&
            tab.lastActiveAt.map { now.timeIntervalSince($0) >= Double(hours) * 3600 } == true
        }.map(\.id)
    }
    public static func cleanable(in space: BrowserSpace, protected: Set<UUID> = []) -> [UUID] {
        var seen = Set(space.tabs.filter { $0.pinned || $0.id == space.selectedTabID || protected.contains($0.id) }.compactMap { $0.url?.absoluteString })
        var result: [UUID] = []
        for tab in space.tabs where !tab.pinned && tab.id != space.selectedTabID && !protected.contains(tab.id) {
            if let url = tab.url {
                if !seen.insert(url.absoluteString).inserted { result.append(tab.id) }
            } else { result.append(tab.id) }
        }
        return result
    }
}
extension BrowserState {
    public mutating func touchTab(_ id: UUID, now: Date = Date()) {
        for i in spaces.indices { if let j = spaces[i].tabs.firstIndex(where: { $0.id == id }) { spaces[i].tabs[j].lastActiveAt = now; return } }
    }
    public mutating func recordVisit(_ id: UUID, url: URL, now: Date = Date()) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        guard let i = spaces.firstIndex(where: { $0.tabs.contains { $0.id == id } }), let tab = spaces[i].tabs.first(where: { $0.id == id }) else { return }
        var history = spaces[i].history ?? []
        let previous = history.first { $0.url == url }
        history.removeAll { $0.url == url }
        history.insert(HistoryEntry(url: url, title: tab.title, visitedAt: now, visits: (previous?.visits ?? 0) + 1), at: 0)
        spaces[i].history = Array(history.prefix(10_000))
    }
    public mutating func archiveTab(_ id: UUID, reason: ArchiveReason, now: Date = Date()) {
        guard let i = spaces.firstIndex(where: { $0.tabs.contains { $0.id == id } }), let tab = spaces[i].tabs.first(where: { $0.id == id }) else { return }
        // Empty tabs have no page to recover. Every real page retains its original title and pin.
        if tab.url != nil { spaces[i].archive = [ArchivedTab(tab: tab, closedAt: now, reason: reason)] + (spaces[i].archive ?? []) }
        closeTab(id)
    }
    @discardableResult public mutating func restoreArchive(_ id: UUID, now: Date = Date()) -> UUID? {
        let i = currentSpaceIndex
        guard let item = spaces[i].archive?.first(where: { $0.id == id }) else { return nil }
        var restored = item.tab; restored.id = UUID(); restored.lastActiveAt = now
        spaces[i].tabs.append(restored); spaces[i].selectedTabID = restored.id
        spaces[i].archive?.removeAll { $0.id == id }
        return restored.id
    }
    public mutating func tidyTabs() {
        let i = currentSpaceIndex
        let pinned = spaces[i].tabs.filter(\.pinned)
        let today = spaces[i].tabs.filter { !$0.pinned }.enumerated().sorted { a, b in
            let ah = a.element.url?.host?.lowercased() ?? "~", bh = b.element.url?.host?.lowercased() ?? "~"
            return ah == bh ? a.offset < b.offset : ah < bh
        }.map(\.element)
        spaces[i].tabs = pinned + today
    }
}
