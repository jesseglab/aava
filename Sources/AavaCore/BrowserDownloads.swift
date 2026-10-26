import Foundation

public enum DownloadStatus: String, Codable, Sendable {
    case waiting, downloading, paused, complete, cancelled, interrupted
    public var active: Bool { self == .waiting || self == .downloading || self == .paused }
}

public struct BrowserDownload: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let profile: UUID
    public var name: String
    public var path: String
    public var received: Int64
    public var total: Int64
    public var status: DownloadStatus
    public var createdAt: Date = Date()
    public var progress: Double? { total > 0 ? min(1, max(0, Double(received) / Double(total))) : nil }
    public init(id: String, profile: UUID, name: String, path: String = "", received: Int64 = 0, total: Int64 = 0, status: DownloadStatus) {
        self.id = id; self.profile = profile; self.name = name; self.path = path
        self.received = received; self.total = total; self.status = status
    }
}

extension BrowserState {
    @discardableResult public mutating func updateDownload(_ item: BrowserDownload) -> Bool {
        guard let index = spaces.firstIndex(where: { $0.profileID == item.profile }) else { return false }
        var items = spaces[index].downloads ?? []
        let previous = items.first(where: { $0.id == item.id })
        var updated = item
        if let previous { updated.createdAt = previous.createdAt }
        items.removeAll { $0.id == item.id }; items.append(updated)
        let finished = items.filter { !$0.status.active }.sorted { $0.createdAt > $1.createdAt }.prefix(80)
        spaces[index].downloads = (items.filter { $0.status.active } + finished).sorted { $0.createdAt > $1.createdAt }
        return item.status == .complete && previous?.status != .complete
    }
    public mutating func recoverDownloadsAfterRestart() {
        for i in spaces.indices {
            guard var items = spaces[i].downloads else { continue }
            for j in items.indices where items[j].status.active { items[j].status = .interrupted }
            spaces[i].downloads = items
        }
    }
}
