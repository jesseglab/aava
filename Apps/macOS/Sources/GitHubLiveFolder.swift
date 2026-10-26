import AppKit
import Security
import SwiftUI

private struct GitHubTokenVault {
    private var service: String { (Bundle.main.bundleIdentifier ?? "app.geeklab.aava.dev") + ".github-live-folder" }
    private func query(_ profile: UUID) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: profile.uuidString] }
    func token(_ profile: UUID) throws -> String {
        var q = query(profile); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else { throw GitHubFailure.message("Connect GitHub for this space first.") }
        return text
    }
    func save(_ token: String, profile: UUID) throws {
        let q = query(profile), value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(q as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var added = q; added.merge(value) { _, new in new }; added[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw GitHubFailure.message("Couldn’t save this connection in Keychain.") }; return
        }
        guard status == errSecSuccess else { throw GitHubFailure.message("Couldn’t update this connection in Keychain.") }
    }
    func remove(_ profile: UUID) throws {
        let status = SecItemDelete(query(profile) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GitHubFailure.message("Couldn’t remove this connection from Keychain.") }
    }
}

@MainActor final class GitHubLiveFolder: ObservableObject {
    struct Snapshot { var items: [GitHubPullRequest]; var updated: Date; var login: String }
    @Published private var snapshots: [UUID: Snapshot] = [:]
    @Published private var errors: [UUID: String] = [:]
    @Published private var busy: Set<UUID> = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]
    private var lastAttempt: [UUID: Date] = [:]
    private let vault = GitHubTokenVault()
    private let api = GitHubAPI()
    func snapshot(_ space: UUID) -> Snapshot? { snapshots[space] }
    func error(_ space: UUID) -> String? { errors[space] }
    func loading(_ space: UUID) -> Bool { busy.contains(space) }
    func suspend(except allowed: UUID?) {
        for id in Array(tasks.keys) where id != allowed { tasks[id]?.cancel(); tasks[id] = nil; generations[id] = nil; busy.remove(id) }
    }
    func purge(_ id: UUID) { tasks[id]?.cancel(); tasks[id] = nil; generations[id] = nil; busy.remove(id); snapshots[id] = nil; errors[id] = nil; lastAttempt[id] = nil }
    func disconnect(space: BrowserSpace) throws { try vault.remove(space.profileID); purge(space.id) }
    func refresh(space: BrowserSpace, force: Bool = false) {
        guard let config = space.githubFolder, config.enabled, !busy.contains(space.id) else { return }
        if !force, let last = lastAttempt[space.id], Date().timeIntervalSince(last) < 300 { return }
        start(space: space, token: nil, configuration: config, connected: nil)
    }
    func connect(space: BrowserSpace, token: String, configuration: GitHubFolderConfiguration, connected: @escaping (GitHubFolderConfiguration) -> Void) {
        start(space: space, token: token.isEmpty ? nil : token, configuration: configuration, connected: connected)
    }
    private func start(space: BrowserSpace, token replacement: String?, configuration: GitHubFolderConfiguration, connected: ((GitHubFolderConfiguration) -> Void)?) {
        tasks[space.id]?.cancel()
        let generation = UUID(); generations[space.id] = generation
        busy.insert(space.id); errors[space.id] = nil; lastAttempt[space.id] = Date()
        tasks[space.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try replacement ?? vault.token(space.profileID)
                let login = try await api.login(token: token)
                let items = try await api.pulls(configuration: configuration, login: login, token: token)
                try Task.checkCancellation()
                guard generations[space.id] == generation else { return }
                if replacement != nil { try vault.save(token, profile: space.profileID) }
                snapshots[space.id] = Snapshot(items: items, updated: Date(), login: login)
                connected?(configuration)
            } catch {
                if !Task.isCancelled && generations[space.id] == generation { errors[space.id] = error.localizedDescription }
            }
            if generations[space.id] == generation { busy.remove(space.id); tasks[space.id] = nil }
        }
    }
}

extension GitHubPRStatus {
    var color: Color { switch self { case .failed: return Color(hex: "D64E5E"); case .pending, .review: return Color(hex: "B88824"); case .approved: return Color(hex: "369664"); case .draft, .unknown: return AavaBrand.secondary } }
    var symbol: String { switch self { case .failed: return "exclamationmark.circle.fill"; case .pending: return "clock.fill"; case .review: return "person.crop.circle"; case .approved: return "checkmark.circle.fill"; case .draft: return "pencil.circle"; case .unknown: return "questionmark.circle" } }
}
struct GitHubFolderTree: View {
    @ObservedObject var store: MacStore
    @ObservedObject var live: GitHubLiveFolder
    let ink: Color
    private var items: [GitHubPullRequest] { live.snapshot(store.space.id)?.items ?? [] }
    private var repos: [String] { Set(items.map(\.repository)).sorted() }
    var body: some View {
        if store.space.githubFolder?.enabled == true {
            VStack(alignment: .leading, spacing: 3) {
                Button { store.openPanel(.github) } label: {
                    HStack(spacing: 8) { Image(systemName: "arrow.triangle.branch"); Text("GitHub").fontWeight(.medium); Spacer(); if live.loading(store.space.id) { ProgressView().controlSize(.mini) } else { Text("\(items.count)").opacity(0.55) } }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 32)
                }
                ForEach(repos, id: \.self) { repo in
                    let pulls = items.filter { $0.repository == repo }
                    let status = GitHubPRStatus.aggregate(pulls.map(\.status))
                    let collapsed = store.space.githubFolder?.collapsedRepositories.contains(repo) == true
                    Button { store.toggleGitHubRepo(repo) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8))
                            Image(systemName: status.symbol).foregroundStyle(live.error(store.space.id) == nil ? status.color : AavaBrand.secondary)
                            Text(repo).lineLimit(1); Spacer(minLength: 0)
                            Text("\(pulls.count)").monospacedDigit().opacity(0.6)
                        }.font(.system(size: 11)).padding(.horizontal, 10).frame(height: 32)
                    }.accessibilityLabel("\(collapsed ? "Expand" : "Collapse") \(repo), \(pulls.count) pull requests, \(status.title)")
                    if !collapsed {
                        ForEach(pulls) { pr in
                            Button { store.openURL(pr.url) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "arrow.triangle.pull").font(.system(size: 12)).foregroundStyle(statusColor(pr))
                                    Text("#\(pr.number) \(pr.title)").lineLimit(1); Spacer(minLength: 0)
                                    Image(systemName: pr.status.symbol).font(.system(size: 9)).foregroundStyle(statusColor(pr))
                                }.font(.system(size: 11)).padding(.leading, 25).padding(.trailing, 8).frame(height: 31)
                            }.help(pr.title + " · " + pr.status.title).accessibilityLabel("\(pr.title), \(pr.status.title)")
                        }
                    }
                }
                if items.isEmpty && !live.loading(store.space.id) { Text(live.error(store.space.id) == nil ? "No matching open PRs" : "Refresh needed · open GitHub settings").font(.system(size: 10)).opacity(0.65).padding(.horizontal, 10).padding(.vertical, 6) }
                if live.error(store.space.id) != nil && !items.isEmpty { Text("Updates paused · showing last results").font(.system(size: 10)).opacity(0.65).padding(.horizontal, 10) }
            }.foregroundStyle(ink)
        }
    }
    private func statusColor(_ pr: GitHubPullRequest) -> Color { live.error(store.space.id) == nil ? pr.status.color : AavaBrand.secondary }
}
struct GitHubFolderSettings: View {
    @ObservedObject var store: MacStore
    @ObservedObject var live: GitHubLiveFolder
    @State private var token = ""
    @State private var filter = GitHubPRFilter.authored
    @State private var repositories = ""
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            panelTitle("GitHub live folder", "Open pull requests, grouped by repository. This connection belongs only to \(store.space.name).")
            Text("Show").font(.system(size: 13, weight: .semibold))
            ForEach(GitHubPRFilter.allCases, id: \.self) { value in
                Button { filter = value } label: { HStack { Text(value.title); Spacer(); if filter == value { Image(systemName: "checkmark") } }.padding(10) }.buttonStyle(AavaHoverButton(active: filter == value))
            }
            TextField("Repositories: owner/repo, owner/another (optional)", text: $repositories).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
            SecureField("GitHub token · leave empty to keep connection", text: $token).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
            Text("Use a GitHub token with access to the repositories, pull requests and their checks. Aava stores it in your Mac Keychain and only makes read requests. It never commits, pushes or merges code.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            Button("Open GitHub token settings") { store.newTab(URL(string: "https://github.com/settings/personal-access-tokens")) }.buttonStyle(AavaHoverButton(inset: 8))
            HStack {
                Button(live.loading(store.space.id) ? "Connecting…" : "Save and refresh") { connect() }.buttonStyle(AavaPrimaryButton()).disabled(live.loading(store.space.id))
                if store.space.githubFolder != nil { Button("Disconnect") { store.disconnectGitHub() }.buttonStyle(AavaHoverButton(inset: 10)) }
            }
            if let error = validation ?? live.error(store.space.id) { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            if let snapshot = live.snapshot(store.space.id) {
                Text("\(snapshot.items.count) open PRs · \(snapshot.login) · updated \(snapshot.updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            }
            Text("Refreshes every 5 minutes while this space is selected and unlocked. Closed or merged PRs leave the live folder; pages you opened stay in your tabs. Status is a summary of checks, review and merge conflicts, not a guarantee that a PR can merge.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            HStack(spacing: 12) { ForEach(GitHubPRStatus.allCases, id: \.self) { status in Image(systemName: status.symbol).foregroundStyle(live.error(store.space.id) == nil ? status.color : AavaSurfaceColors.secondary).help(status.title).accessibilityLabel(status.title) } }
        }.onAppear { if let config = store.space.githubFolder { filter = config.filter; repositories = config.repositories.joined(separator: ", ") } }
            .onDisappear { token = "" }
    }
    private func connect() {
        let repos = repositories.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard repos.allSatisfy(GitHubFolderConfiguration.validRepository), filter != .repository || !repos.isEmpty else { validation = "Use owner/repo names. Choose at least one repository for All PRs."; return }
        var config = store.space.githubFolder ?? GitHubFolderConfiguration(); config.enabled = true; config.filter = filter; config.repositories = Array(Set(repos)).sorted()
        validation = nil; store.connectGitHub(token: token.trimmingCharacters(in: .whitespacesAndNewlines), configuration: config); token = ""
    }
}
