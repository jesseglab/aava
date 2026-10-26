import Foundation

public struct ArcImportResult {
    public var spaces: [BrowserSpace]
    public var skippedItems: Int
    public var tabCount: Int { spaces.reduce(0) { $0 + $1.tabs.filter { $0.url != nil }.count } }
    public var savedCount: Int { spaces.reduce(0) { $0 + $1.saved.count } }
}

public enum ArcImporter {
    public enum Failure: LocalizedError {
        case invalid, noSpaces, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalid: return "This file isn't a supported Arc sidebar. Choose StorableSidebar.json from Arc’s application support folder."
            case .noSpaces: return "No named Arc spaces were found in this sidebar file."
            case .tooLarge: return "This sidebar file is too large to import safely."
            }
        }
    }
    /// Arc encodes UUID-keyed dictionaries as alternating key/value arrays.
    private static func pairs(_ value: Any?) -> [(String, [String: Any])] {
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().compactMap { key in (dictionary[key] as? [String: Any]).map { (key, unwrap($0)) } }
        }
        guard let array = value as? [Any] else { return [] }
        var result: [(String, [String: Any])] = []
        for i in stride(from: 0, to: max(0, array.count-1), by: 2) {
            if let key = array[i] as? String, let item = array[i+1] as? [String: Any] { result.append((key, unwrap(item))) }
        }
        return result
    }
    private static func unwrap(_ item: [String: Any]) -> [String: Any] { item["value"] as? [String: Any] ?? item }
    public static func read(_ data: Data) throws -> ArcImportResult {
        guard data.count <= 32 * 1024 * 1024 else { throw Failure.tooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let sidebar = root["sidebar"] as? [String: Any], let containers = sidebar["containers"] as? [Any] else { throw Failure.invalid }
        var items: [String: [String: Any]] = [:], spaces: [String: [String: Any]] = [:], order: [String] = []
        var favorites: [String:String] = [:]
        func profileKey(_ value: Any?) -> String? {
            guard let value = value as? [String:Any], let data = try? JSONSerialization.data(withJSONObject:value,options:.sortedKeys) else { return nil }
            return String(decoding:data,as:UTF8.self)
        }
        func collectFavorites(_ value: Any?) {
            guard let array = value as? [Any] else { return }
            for i in stride(from:0,to:max(0,array.count-1),by:2) {
                if let key = profileKey(array[i]), let root = array[i+1] as? String { favorites[key] = root }
            }
        }
        // Sync is fallback; live local containers override it.
        if let sync = root["sidebarSyncState"] as? [String: Any] {
            for (key, item) in pairs(sync["items"]) { items[key] = item }
            for (key, item) in pairs(sync["spaceModels"]) { spaces[key] = item }
            let container = (sync["container"] as? [String: Any]).map(unwrap)
            order = container?["orderedSpaceIDs"] as? [String] ?? []
            collectFavorites(container?["topAppsContainerIDs"])
        }
        for raw in containers {
            guard let container = raw as? [String: Any] else { continue }
            collectFavorites(container["topAppsContainerIDs"])
            for (key, item) in pairs(container["items"]) { items[key] = item }
            for (key, item) in pairs(container["spaces"]) { spaces[key] = item; if !order.contains(key) { order.append(key) } }
        }
        for key in spaces.keys.sorted() where !order.contains(key) { order.append(key) }
        var imported: [BrowserSpace] = [], skipped = 0
        for key in order {
            guard let source = spaces[key], let name = source["title"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let custom = source["customInfo"] as? [String: Any] ?? [:]
            let icon = custom["iconType"] as? [String: Any] ?? [:]
            let emoji = icon["emoji"] as? String ?? "◌"
            var space = BrowserSpace(name: name, emoji: emoji, theme: .tide)
            space.arcSourceID = key
            if let profile = source["profile"] as? [String: Any] {
                if profile["default"] != nil { space.arcProfileDirectory = "Default" }
                else if let custom = profile["custom"] as? [String: Any], let inner = custom["_0"] as? [String: Any] {
                    space.arcProfileDirectory = inner["directoryBasename"] as? String
                }
            }
            space.tabs = []; space.saved = []
            if let theme = custom["windowTheme"] as? [String: Any], let palette = theme["primaryColorPalette"] as? [String: Any] {
                func color(_ name: String) -> String? {
                    guard let c = palette[name] as? [String: Any], let r = c["red"] as? Double, let g = c["green"] as? Double, let b = c["blue"] as? Double, [r,g,b].allSatisfy({ $0.isFinite }) else { return nil }
                    return [r,g,b].map { String(format:"%02X",Int((min(1,max(0,$0))*255).rounded())) }.joined()
                }
                if let top = color("midTone"), let bottom = color("tintedLight") { space.theme = SpaceTheme(top: top, bottom: bottom) }
            }
            var roots: [(String,Bool)] = []
            if let array = source["newContainerIDs"] as? [Any] {
                for i in stride(from: 0, to: max(0,array.count-1), by: 2) {
                    if let kind = array[i] as? [String: Any], let id = array[i+1] as? String { roots.append((id,kind["pinned"] != nil)) }
                }
            }
            if roots.isEmpty, let legacy = source["containerIDs"] as? [String] {
                for i in stride(from:0,to:max(0,legacy.count-1),by:2) { roots.append((legacy[i+1],legacy[i].lowercased().contains("pinned") && !legacy[i].lowercased().contains("unpinned"))) }
            }
            var visited: Set<String> = []
            func walk(_ id: String, parent: UUID?, pinned: Bool, depth: Int) {
                guard depth < 64, visited.insert(id).inserted, let item = items[id] else { skipped += 1; return }
                let detail = item["data"] as? [String: Any] ?? [:]
                let children = item["childrenIds"] as? [String] ?? []
                if let tab = detail["tab"] as? [String: Any] {
                    guard let address = tab["savedURL"] as? String, let url = URL(string: address), ["https","http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { skipped += 1; return }
                    let title = item["title"] as? String ?? tab["savedTitle"] as? String ?? url.host ?? "Imported tab"
                    if let parent { space.saved.append(SavedItem(title:title,url:url,parentID:parent)) }
                    else { space.tabs.append(BrowserTab(title:title,url:url,pinned:pinned)) }
                } else if detail["list"] != nil || detail["splitView"] != nil {
                    let folder = SavedItem(title: item["title"] as? String ?? (detail["splitView"] != nil ? "Split view" : "Folder"), parentID: parent)
                    space.saved.append(folder)
                    children.forEach { walk($0,parent:folder.id,pinned:pinned,depth:depth+1) }
                } else if detail["itemContainer"] != nil {
                    children.forEach { walk($0,parent:parent,pinned:pinned,depth:depth+1) }
                } else { skipped += 1 }
            }
            if let profile = profileKey(source["profile"]), let root = favorites[profile], let children = items[root]?["childrenIds"] as? [String], !children.isEmpty {
                let folder = SavedItem(title:"Favorites")
                space.saved.append(folder)
                walk(root,parent:folder.id,pinned:true,depth:0)
            }
            for (id,pinned) in roots { walk(id,parent:nil,pinned:pinned,depth:0) }
            if space.tabs.isEmpty { space.tabs = [BrowserTab()] }
            space.selectedTabID = space.tabs.first?.id
            imported.append(space)
        }
        guard !imported.isEmpty else { throw Failure.noSpaces }
        return ArcImportResult(spaces:imported,skippedItems:skipped)
    }
}
