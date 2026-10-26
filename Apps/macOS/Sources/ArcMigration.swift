import SwiftUI
import Security
import LocalAuthentication

@MainActor final class ArcMigration: ObservableObject {
    enum Failure: LocalizedError {
        case cannotSave, keychain(OSStatus), noSelection
        var errorDescription: String? {
            switch self {
            case .cannotSave: return "Resolve the saved-session error before importing."
            case .keychain(let status): return "Arc’s Safe Storage key was not available (\(status)). Allow access in macOS Keychain, or import without website sessions."
            case .noSelection: return "Select a profile and at least one thing to bring over."
            }
        }
    }
    @Published var path = "~/Library/Application Support/Arc/User Data"
    @Published var profiles: [ArcProfileSummary] = []
    @Published var selected = ""
    @Published var name = ""
    @Published var bookmarks = true
    @Published var history = true
    @Published var extensions = true
    @Published var sessions = false
    @Published var busy = false
    @Published var status: String?
    @Published var error: String?
    @Published var importedSpace: UUID?
    private var scannedRoot: URL?
    private var pending: (token: String, space: BrowserSpace, summary: String, skipped: Int)?
    var chosen: ArcProfileSummary? { profiles.first { $0.id == selected } }
    private var root: URL { URL(fileURLWithPath: (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath) }
    func scan() {
        guard !busy else { return }
        busy = true; error = nil; status = nil; importedSpace = nil; profiles = []; selected = ""
        let source = root
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try ArcProfileImport.scan(root: source) }.value
                scannedRoot = source; profiles = result; selected = result.first?.id ?? ""; name = "Arc · " + (result.first?.name ?? "Imported")
                if result.isEmpty { error = "No Arc profiles found. Choose the User Data folder inside Arc’s application support folder." }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func start(store: MacStore) {
        guard !busy, let profile = chosen, bookmarks || history || extensions || sessions else { return }
        guard scannedRoot == root else { error = "The source folder changed. Scan again before importing."; return }
        busy = true; error = nil; status = sessions ? "Reading Arc. macOS may ask for permission to unlock its sessions…" : "Reading Arc…"; importedSpace = nil
        let source = root, includeBookmarks = bookmarks, includeHistory = history, includeExtensions = extensions, includeSessions = sessions
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> (BrowserSpace, [ArcSessionCookie], Int) in
                    let directory = try ArcProfileImport.profileURL(root: source, directory: profile.id)
                    var space = BrowserSpace(name: title.isEmpty ? "Arc · " + profile.name : title, emoji: "🧳", theme: .tide)
                    space.arcProfileDirectory = profile.id
                    if includeBookmarks {
                        let file = try ArcProfileImport.file("Bookmarks", in: directory)
                        if FileManager.default.fileExists(atPath: file.path) { space.saved = try ArcProfileImport.readBookmarks(file) }
                    }
                    if includeHistory { space.history = try ArcProfileImport.history(ArcProfileImport.file("History", in: directory)) }
                    if includeExtensions { space.arcExtensions = try ArcProfileImport.extensions(directory) }
                    var cookies: [ArcSessionCookie] = [], skipped = 0
                    if includeSessions {
                        let network = try ArcProfileImport.file("Network/Cookies", in: directory)
                        let file = FileManager.default.fileExists(atPath: network.path) ? network : try ArcProfileImport.file("Cookies", in: directory)
                        if FileManager.default.fileExists(atPath: file.path) {
                            var key = try Self.arcKey()
                            defer { key.resetBytes(in: 0..<key.count) }
                            let result = try ArcProfileImport.cookies(file, password: key)
                            cookies = result.items; skipped = result.skipped
                        }
                    }
                    return (space, cookies, skipped)
                }.value
                let (space, cookies, skipped) = result
                let summary = "\(space.saved.filter { !$0.isFolder }.count) bookmarks · \(space.history?.count ?? 0) history entries · \(space.arcExtensions?.count ?? 0) extensions on your restore list."
                if includeSessions && !cookies.isEmpty {
                    let token = UUID().uuidString
                    pending = (token, space, summary, skipped)
                    status = "Saving website sessions into a new, separate space…"
                    let data = try JSONEncoder().encode(cookies)
                    guard let json = String(data: data, encoding: .utf8) else { throw ArcProfileImport.Failure.encryption }
                    space.profileID.uuidString.withCString { profile in json.withCString { json in token.withCString { AavaEngineImportArcCookies(profile, json, $0) } } }
                } else {
                    try store.commitArcProfile(space)
                    importedSpace = space.id
                    status = summary + (includeSessions ? " No website cookies transferred; \(skipped) skipped. You may need to sign in again." : "")
                    busy = false
                }
            } catch { pending = nil; busy = false; status = nil; self.error = error.localizedDescription }
        }
    }
    nonisolated private static func arcKey() throws -> Data {
        let context = LAContext()
        context.localizedReason = "Bring Arc website sessions into your new Aava space."
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Arc Safe Storage", kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else { throw Failure.keychain(status) }
        return data
    }
    func cookieResult(token: String, json: String, store: MacStore) {
        guard let pending, pending.token == token else { return }
        struct Result: Decodable { let saved: Int; let failed: Int; let error: String? }
        guard let data = json.data(using: .utf8), let result = try? JSONDecoder().decode(Result.self, from: data) else { return }
        self.pending = nil; busy = false
        if let message = result.error { error = message; status = nil; return }
        do {
            try store.commitArcProfile(pending.space)
            importedSpace = pending.space.id
            status = pending.summary + " \(result.saved) website cookies transferred; \(result.failed + pending.skipped) skipped. Some sites may still ask you to sign in."
        } catch { self.error = "The space could not be saved. Imported cookies remain in an unused isolated profile; no existing space was changed. " + error.localizedDescription; status = nil }
    }
}

struct ArcMigrationView: View {
    @ObservedObject var store: MacStore
    @ObservedObject var migration: ArcMigration
    private var restored: [ArcExtensionInfo] { store.locked ? [] : store.space.arcExtensions ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            panelTitle("More of Arc. At home in Aava.", "Bring one Arc profile into a new, independent space. Your existing spaces and Arc data stay unchanged.")
            VStack(alignment: .leading, spacing: 12) {
                Text("Arc’s User Data folder").font(.system(size: 12, weight: .semibold))
                TextField("Arc User Data folder", text: $migration.path).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius)).disabled(migration.busy)
                Button(migration.profiles.isEmpty ? "Find profiles" : "Scan again") { migration.scan() }.buttonStyle(AavaHoverButton(inset: 10)).disabled(migration.busy)
            }
            if !migration.profiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose a profile").font(.system(size: 13, weight: .semibold))
                    ForEach(migration.profiles) { profile in
                        Button {
                            migration.selected = profile.id; migration.name = "Arc · " + profile.name
                        } label: {
                            HStack {
                                Image(systemName: migration.selected == profile.id ? "checkmark.circle.fill" : "circle")
                                Text(profile.name); Spacer(); Text(profile.id).foregroundStyle(AavaSurfaceColors.secondary)
                            }.padding(10).frame(maxWidth: .infinity)
                        }.buttonStyle(AavaHoverButton(active: migration.selected == profile.id)).disabled(migration.busy)
                    }
                }
                if let profile = migration.chosen {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("New space name", text: $migration.name).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
                        Toggle("Bookmarks & folders · \(profile.bookmarks.filter { !$0.isFolder }.count) pages", isOn: $migration.bookmarks)
                        Toggle("Browsing history · up to \(min(profile.historyCount ?? 10000, 10000)) entries", isOn: $migration.history)
                        Toggle("Extension restore list · \(profile.extensions.count) extensions", isOn: $migration.extensions)
                        Text("Saves extension names and official store links. Extensions are not installed automatically; compatibility and installation permissions still need review.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
                        Toggle("Try bringing website sessions · \(profile.cookieCount.map(String.init) ?? "unknown") cookies", isOn: $migration.sessions)
                        Text("Optional. macOS may ask to unlock Arc Safe Storage. Only this new space receives the sessions. Expired, partitioned and unsupported cookies are skipped. Passkeys and local-storage sign-ins do not transfer.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
                        ForEach(profile.notes, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary) }
                        Text("For the most complete import, quit Arc first. Importing again creates another space.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
                        Button("Import into new space") { migration.start(store: store) }.buttonStyle(AavaPrimaryButton()).disabled(!migration.bookmarks && !migration.history && !migration.extensions && !migration.sessions)
                    }.disabled(migration.busy)
                }
            }
            if migration.busy { HStack { ProgressView().controlSize(.small); Text("Working…").font(.system(size: 12)) } }
            if let status = migration.status { Text(status).font(.system(size: 13)).textSelection(.enabled) }
            if let error = migration.error { Text(error).font(.system(size: 13)).foregroundStyle(.red).textSelection(.enabled) }
            if let id = migration.importedSpace {
                Button("Open imported space") { store.dismissPanels(); store.switchSpace(id); store.openPanel(.arcData) }.buttonStyle(AavaPrimaryButton())
            }
            Divider()
            panelTitle("Finish settling in", "Passwords and extensions need a separate step in each space.")
            Text("Export saved passwords from Arc’s password manager, then import that CSV into Aava’s password manager in the intended space. The CSV contains readable passwords: keep it private and remove it after importing. Passkeys remain with their original provider.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            Button("Open this space’s password manager") { store.dismissPanels(); store.newTab(URL(string: "chrome://password-manager/settings")) }.buttonStyle(AavaHoverButton(inset: 10)).disabled(store.locked)
            if !restored.isEmpty {
                Text("\(store.space.name)’s extension restore list").font(.system(size: 14, weight: .semibold))
                ForEach(restored) { item in
                    HStack {
                        Image(systemName: "puzzlepiece.extension").foregroundStyle(AavaSurfaceColors.secondary)
                        VStack(alignment: .leading, spacing: 4) { Text(item.name); Text("Version " + item.version).font(.caption).foregroundStyle(AavaSurfaceColors.secondary) }
                        Spacer()
                        Button("View in store") { if let url = item.storeURL { store.dismissPanels(); store.newTab(url) } }.buttonStyle(AavaHoverButton(inset: 8))
                    }.padding(.vertical, 5)
                }
            }
        }
    }
}
