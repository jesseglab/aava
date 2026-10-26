import Foundation

public enum IconStyle: String, Codable, CaseIterable, Sendable {
    case lucide, heroicons, emoji
    public var title: String { rawValue == "heroicons" ? "Heroicons" : rawValue.capitalized }
}

public struct SpaceTheme: Codable, Equatable, Sendable {
    public var top: String
    public var bottom: String
    public var darkText: Bool
    public init(top: String, bottom: String, darkText: Bool = true) {
        self.top = top; self.bottom = bottom; self.darkText = darkText
    }
    public static let tide = SpaceTheme(top: "ACC5CC", bottom: "D6E0D8")
    public static let dusk = SpaceTheme(top: "534F72", bottom: "9B8599", darkText: false)
    public static let apricot = SpaceTheme(top: "E8BA9E", bottom: "F0DBB7")
    public static let sage = SpaceTheme(top: "B8C5AC", bottom: "E2DFC9")
}

public struct BrowserTab: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL?
    public var pinned: Bool
    public var lastActiveAt: Date?
    public var pinnedURL: URL?
    public var tile: PinnedTileStyle?
    public var displayTitle: String {
        let name = tile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return pinned && !name.isEmpty ? name : title
    }
    public init(id: UUID = UUID(), title: String = "New tab", url: URL? = nil, pinned: Bool = false) {
        self.id = id; self.title = title; self.url = url; self.pinned = pinned; self.lastActiveAt = Date(); self.pinnedURL = pinned ? url : nil
    }
}

public struct SavedItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL?
    public var parentID: UUID?
    public var isFolder: Bool { url == nil }
    public init(id: UUID = UUID(), title: String, url: URL? = nil, parentID: UUID? = nil) {
        self.id = id; self.title = title; self.url = url; self.parentID = parentID
    }
}

public struct BrowserSpace: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var profileID: UUID
    public var name: String
    public var emoji: String
    public var theme: SpaceTheme
    public var iconStyle: IconStyle
    public var tabs: [BrowserTab]
    public var selectedTabID: UUID?
    public var saved: [SavedItem]
    public var privacy: PrivateSpaceSettings?
    public var arcSourceID: String?
    public var arcProfileDirectory: String?
    public var arcExtensions: [ArcExtensionInfo]?
    public var collapsedFolderIDs: Set<UUID>?
    public var archive: [ArchivedTab]?
    public var history: [HistoryEntry]?
    public var autoArchiveHours: Int?
    public var sameSiteLinkChoices: [String: SameSiteLinkChoice]?
    public var downloads: [BrowserDownload]?
    public var commandSelections: [String: Int]?
    public var githubFolder: GitHubFolderConfiguration?
    public var appearance: SpaceAppearance?
    public var liquidGlass: Bool?
    public var usesLiquidGlass: Bool { liquidGlass ?? false }
    public init(id: UUID = UUID(), profileID: UUID = UUID(), name: String, emoji: String,
                theme: SpaceTheme, iconStyle: IconStyle = .lucide) {
        self.id = id; self.profileID = profileID; self.name = name; self.emoji = emoji
        self.theme = theme; self.iconStyle = iconStyle
        let tab = BrowserTab()
        self.tabs = [tab]; self.selectedTabID = tab.id; self.saved = []
    }
}

public struct BrowserState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var spaces: [BrowserSpace]
    public var selectedSpaceID: UUID
    public var currentSpaceIndex: Int { spaces.firstIndex { $0.id == selectedSpaceID } ?? 0 }
    public var currentSpace: BrowserSpace { spaces[currentSpaceIndex] }
    public var currentTab: BrowserTab? { currentSpace.tabs.first { $0.id == currentSpace.selectedTabID } }

    public init() {
        var work = BrowserSpace(name: "Work", emoji: "🌊", theme: .tide)
        let projects = SavedItem(title: "Projects")
        let research = SavedItem(title: "Research", parentID: projects.id)
        work.saved = [projects, research,
                      SavedItem(title: "Apple Developer", url: URL(string: "https://developer.apple.com"), parentID: research.id),
                      SavedItem(title: "MDN Web Docs", url: URL(string: "https://developer.mozilla.org"), parentID: research.id)]
        let studio = BrowserSpace(name: "Studio", emoji: "🌙", theme: .dusk, iconStyle: .heroicons)
        let personal = BrowserSpace(name: "Personal", emoji: "🍑", theme: .apricot, iconStyle: .emoji)
        spaces = [work, studio, personal]; selectedSpaceID = work.id
    }

    public mutating func normalize() {
        if spaces.isEmpty { self = BrowserState(); return }
        if !spaces.contains(where: { $0.id == selectedSpaceID }) { selectedSpaceID = spaces[0].id }
        var usedProfiles: Set<UUID> = []
        for i in spaces.indices {
            if !usedProfiles.insert(spaces[i].profileID).inserted {
                spaces[i].profileID = UUID()
                usedProfiles.insert(spaces[i].profileID)
            }
            if let privacy = spaces[i].privacy { spaces[i].privacy = PrivateSpaceSettings(idleMinutes: privacy.idleMinutes, stayOn: privacy.stayOn ?? false) }
            for j in spaces[i].tabs.indices where spaces[i].tabs[j].lastActiveAt == nil { spaces[i].tabs[j].lastActiveAt = Date() }
            if spaces[i].tabs.isEmpty { spaces[i].tabs = [BrowserTab()] }
            if !spaces[i].tabs.contains(where: { $0.id == spaces[i].selectedTabID }) {
                spaces[i].selectedTabID = spaces[i].tabs[0].id
            }
        }
    }

    @discardableResult public mutating func addTab(url: URL? = nil) -> UUID {
        let tab = BrowserTab(title: url?.host ?? "New tab", url: url)
        spaces[currentSpaceIndex].tabs.append(tab)
        spaces[currentSpaceIndex].selectedTabID = tab.id
        return tab.id
    }

    public mutating func closeTab(_ id: UUID) {
        for i in spaces.indices where spaces[i].tabs.contains(where: { $0.id == id }) {
            let index = spaces[i].tabs.firstIndex { $0.id == id }!
            spaces[i].tabs.remove(at: index)
            if spaces[i].selectedTabID == id {
                spaces[i].selectedTabID = spaces[i].tabs.isEmpty ? nil : spaces[i].tabs[min(index, spaces[i].tabs.count - 1)].id
            }
        }
        normalize()
    }

    public mutating func updateTab(_ id: UUID, url: URL?, title: String?) {
        for i in spaces.indices {
            guard let j = spaces[i].tabs.firstIndex(where: { $0.id == id }) else { continue }
            if let url { spaces[i].tabs[j].url = url }
            if let title, !title.isEmpty { spaces[i].tabs[j].title = title }
            return
        }
    }

    @discardableResult public mutating func renameSaved(_ id: UUID, title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = currentSpace.saved.firstIndex(where: { $0.id == id }) else { return false }
        spaces[currentSpaceIndex].saved[index].title = String(clean.prefix(200))
        return true
    }

    public func canMoveSaved(_ id: UUID, to parent: UUID?) -> Bool {
        let items = currentSpace.saved
        guard items.contains(where: { $0.id == id }) else { return false }
        guard let parent else { return true }
        guard items.contains(where: { $0.id == parent && $0.isFolder }) else { return false }
        var cursor: UUID? = parent
        var visited: Set<UUID> = []
        while let node = cursor {
            guard node != id, visited.insert(node).inserted else { return false }
            cursor = items.first(where: { $0.id == node })?.parentID
        }
        return true
    }

    @discardableResult public mutating func moveSaved(_ id: UUID, to parent: UUID?) -> Bool {
        guard canMoveSaved(id, to: parent), let index = currentSpace.saved.firstIndex(where: { $0.id == id }) else { return false }
        spaces[currentSpaceIndex].saved[index].parentID = parent
        return true
    }

    public mutating func toggleFolder(_ id: UUID) {
        guard currentSpace.saved.contains(where: { $0.id == id && $0.isFolder }) else { return }
        var collapsed = currentSpace.collapsedFolderIDs ?? []
        if !collapsed.insert(id).inserted { collapsed.remove(id) }
        spaces[currentSpaceIndex].collapsedFolderIDs = collapsed
    }

    public mutating func deleteSaved(_ id: UUID) {
        var removal: Set<UUID> = [id]
        let items = currentSpace.saved
        var count: Int
        repeat {
            count = removal.count
            for item in items where item.parentID.map(removal.contains) == true { removal.insert(item.id) }
        } while count != removal.count
        spaces[currentSpaceIndex].saved.removeAll { removal.contains($0.id) }
        spaces[currentSpaceIndex].collapsedFolderIDs?.subtract(removal)
    }
}

public enum NavigationInput {
    public static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil { return url }
        if text.contains("://") || text.lowercased().hasPrefix("javascript:") || text.lowercased().hasPrefix("data:") { return nil }
        if !text.contains(where: \.isWhitespace), (text.contains(".") || text.hasPrefix("localhost")),
           let url = URL(string: "https://" + text), url.host != nil { return url }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }
}

public struct StateRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> BrowserState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return BrowserState() }
        var state = try JSONDecoder().decode(BrowserState.self, from: Data(contentsOf: fileURL))
        guard state.version == 1 else { throw CocoaError(.fileReadUnknown) }
        state.normalize()
        return state
    }
    public func save(_ state: BrowserState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
