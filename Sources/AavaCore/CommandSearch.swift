import Foundation

public struct CommandResult: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case tab, saved, history, archive, navigate, action }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var url: URL?
    public var target: UUID?
    public init(id: String, kind: Kind, title: String, detail: String, url: URL? = nil, target: UUID? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.url = url; self.target = target
    }
}
public enum CommandSearch {
    public static let actions: [(String, String)] = [
        ("library", "History and archive"), ("tidy", "Tidy up tabs"), ("clean", "Clean tabs"),
        ("settings", "Settings"), ("github", "Configure GitHub live folder"), ("extensions", "Extensions"),
        ("downloads", "Downloads"), ("pin", "Pin or unpin tab"), ("reset-pin", "Reset pinned tab"),
        ("copy", "Copy URL"), ("save", "Save page to sidebar"), ("folder", "New folder"),
        ("space", "Create or edit space"), ("pip", "Picture in Picture"), ("devtools", "Developer tools"),
        ("import", "Import Arc spaces"), ("lock", "Lock private spaces")
    ]
    public static func results(query: String, in space: BrowserSpace, limit: Int = 8) -> [CommandResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidates: [(CommandResult, Int)] = []
        func add(_ result: CommandResult, base: Int) {
            let title = result.title.lowercased(), address = result.url?.absoluteString.lowercased() ?? ""
            let host = result.url?.host?.lowercased() ?? ""
            guard q.isEmpty || title.contains(q) || address.contains(q) || (result.kind == .action && result.id.contains(q)) else { return }
            let match = title == q || host == q ? 80 : title.hasPrefix(q) || host.hasPrefix(q) ? 35 : 0
            let learned = min(50, (space.commandSelections?[q + "|" + result.id] ?? 0) * 10)
            candidates.append((result, base + match + learned))
        }
        if q.hasSuffix("."), let ordinal = Int(q.dropLast()), ordinal > 0, ordinal <= space.tabs.count {
            let tab = space.tabs[ordinal - 1]
            return [CommandResult(id: "tab:" + tab.id.uuidString, kind: .tab, title: tab.displayTitle, detail: "Switch to tab", url: tab.url, target: tab.id)]
        }
        for tab in space.tabs.sorted(by: { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }) where tab.url != nil { add(CommandResult(id: "tab:" + tab.id.uuidString, kind: .tab, title: tab.displayTitle, detail: "Switch to tab", url: tab.url, target: tab.id), base: 100) }
        let openURLs = Set(space.tabs.compactMap(\.url))
        for item in space.saved where item.url != nil && !openURLs.contains(item.url!) { add(CommandResult(id: "saved:" + item.id.uuidString, kind: .saved, title: item.title, detail: "Saved", url: item.url), base: 65) }
        for item in (space.history ?? []).prefix(10_000) where !openURLs.contains(item.url) { add(CommandResult(id: "history:" + item.url.absoluteString, kind: .history, title: item.title, detail: "History", url: item.url), base: 45) }
        for item in space.archive ?? [] { add(CommandResult(id: "archive:" + item.id.uuidString, kind: .archive, title: item.tab.title, detail: "Restore tab", url: item.tab.url, target: item.id), base: 40) }
        if !q.isEmpty { for (id, title) in actions { add(CommandResult(id: id, kind: .action, title: title, detail: "Action"), base: 70) } }
        var results = candidates.enumerated().sorted { $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 > $1.element.1 }.map { $0.element.0 }
        // Only one suggestion per URL after open tabs; duplicate open tabs remain independently selectable.
        var seen: Set<URL> = []
        results = results.filter { result in guard let url = result.url, result.kind != .tab else { return true }; return seen.insert(url).inserted }
        if let url = NavigationInput.resolve(query) {
            let isSearch = url.host == "duckduckgo.com" && !q.contains("duckduckgo.com")
            let result = CommandResult(id: "navigate", kind: .navigate, title: isSearch ? query : url.absoluteString, detail: isSearch ? "Search DuckDuckGo" : "Open website", url: url)
            results.insert(result, at: min(results.isEmpty ? 0 : 1, results.count))
        }
        if results.isEmpty { results = [CommandResult(id: "library", kind: .action, title: "History and archive", detail: "⌘ Y"), CommandResult(id: "settings", kind: .action, title: "Settings", detail: "⌘ ,")] }
        return Array(results.prefix(limit))
    }
}
