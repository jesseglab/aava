import AppKit
import SwiftUI

@MainActor final class MacStore: ObservableObject {
    @Published var state: BrowserState
    @Published var backgroundError: String?
    @Published var address = ""
    @Published var commandNewTab = false
    @Published var commandIndex = 0
    @Published var librarySection = "History"
    let arcMigration = ArcMigration()
    let github = GitHubLiveFolder()
    private var cleanupTimer: Timer?
    private var pendingArchive: [UUID: ArchiveReason] = [:]
    private var activeDownloads: Set<UUID> = []
    @Published var showSearch = false
    @Published var showSettings = false
    @Published var panel: AavaPanel?
    @Published var prompts: [AavaPrompt] = []
    @Published var settingsSection = "Appearance"
    let faviconCache: FaviconCache
    let notifications: AavaNotifications
    let linkChoices = AavaLinkChoices()
    @Published var downloadTrayExpanded = false
    var hasPanel: Bool { showSettings || showAbout || showPrivateSetup || importPreview != nil || message != nil || panel != nil || !prompts.isEmpty }
    func dismissPanels() {
        showSettings = false; showAbout = false; showPrivateSetup = false
        importPreview = nil; message = nil; panel = nil
    }
    func openSettings(_ section: String = "Appearance") { dismissPanels(); showSearch = false; settingsSection = section; showSettings = true }
    func openPanel(_ value: AavaPanel) { dismissPanels(); showSearch = false; panel = value }
    func resolvePrompt(_ prompt: AavaPrompt, allow: Bool, value: String = "") {
        prompts.removeAll { $0.token == prompt.token }
        let permitted = allow && state.spaces.contains { $0.profileID.uuidString == prompt.profile && !isLocked($0.id) }
        prompt.token.withCString { token in value.withCString { AavaEngineResolvePrompt(token, permitted, $0) } }
    }
    func favicon(_ url: URL?) -> NSImage? { locked ? nil : faviconCache.image(url, profile: space.profileID) }

    @Published var loading = false
    @Published var canBack = false
    @Published var canForward = false
    @Published var message: String?
    @Published var findText = ""
    @Published var showFind = false
    @Published var copied = false
    @Published var callPolicy = CallPopoutPolicy()
    @Published var privacyPolicy = PrivateSpacePolicy()
    @Published var showPrivateSetup = false
    @Published var privateError: String?
    @Published var importPreview: ArcImportResult?
    @Published var onboarding: OnboardingState
    @Published var showOnboarding: Bool
    @Published var showAbout = false
    @Published var onboardingImportedCount = 0
    private let onboardingRepository: OnboardingRepository
    private var privateTarget: UUID?
    private var privateDraft: BrowserSpace?
    private let vault = PrivateSpaceVault()
    private var lockTimer: Timer?
    private var inputMonitor: Any?
    private var lockObservers: [NSObjectProtocol] = []
    private var views: [UUID: NSView] = [:]
    private var loaded: Set<UUID> = []
    private var closing: Set<UUID> = []
    private var sleeping: Set<UUID> = []
    private let repository: StateRepository
    var spaceDirection = 1
    private var spaceActivation: DispatchWorkItem?
    private var persistTask: Task<Void, Never>?
    private var mayPersist = true
    var space: BrowserSpace { state.currentSpace }
    var locked: Bool { isLocked(space.id) }
    func isLocked(_ id: UUID) -> Bool {
        guard state.spaces.first(where: { $0.id == id })?.privacy != nil else { return false }
        return !privacyPolicy.isUnlocked(id, now: Date())
    }
    func mayAccess(_ id: UUID) -> Bool {
        guard let owner = state.spaces.first(where: { $0.tabs.contains(where: { $0.id == id }) }) else { return false }
        return !isLocked(owner.id)
    }
    var tab: BrowserTab? { locked ? nil : state.currentTab }
    var currentURL: URL? { tab?.url }
    var loadedCount: Int { loaded.count }

    init() {
        let root = ProcessInfo.processInfo.environment["AAVA_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aava")
        notifications = AavaNotifications(root: root)
        faviconCache = FaviconCache(root: root.appendingPathComponent("Favicons"))
        repository = StateRepository(fileURL: root.appendingPathComponent("desktop-session.json"))
        onboardingRepository = OnboardingRepository(fileURL: root.appendingPathComponent("onboarding.json"))
        let welcome = (try? onboardingRepository.load()) ?? OnboardingState()
        onboarding = welcome
        showOnboarding = welcome.needsPresentation
        do { state = try repository.load(); state.recoverDownloadsAfterRestart() }
        catch { state = BrowserState(); mayPersist = false; message = "Your saved session could not be read. It has been preserved; this session will not overwrite it." }
    }
    func moveOnboarding(forward: Bool) {
        if forward { onboarding.advance() } else { onboarding.back() }
        do { try onboardingRepository.save(onboarding) }
        catch { message = "Setup progress couldn’t be saved: \(error.localizedDescription)" }
    }
    func finishOnboarding() {
        var finished = onboarding; finished.complete()
        do {
            try onboardingRepository.save(finished)
            onboarding = finished; showOnboarding = false
            activate()
        } catch { message = "Setup couldn’t be saved. Please try again. \(error.localizedDescription)" }
    }
    func replayOnboarding() {
        dismissPanels(); showSearch = false; showFind = false
        onboarding.replay(); onboardingImportedCount = 0
        AavaEngineOverlay(true); showOnboarding = true
    }
    func spaceEmoji(_ emoji: String) {
        guard !locked, !emoji.isEmpty else { return }
        state.spaces[state.currentSpaceIndex].emoji = String(emoji.prefix(1)); persist()
    }
    func startPrivacyMonitoring() {
        lockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expirePrivateSpaces() }
        }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.expirePrivateSpaces()
                let profile = AavaEngineFocusedProfile().map { String(cString:$0) }
                let owner = self.state.spaces.first { $0.profileID.uuidString == profile }
                if let id = owner?.id ?? (NSApp.keyWindow?.title == "Aava" ? self.space.id : nil) {
                    self.privacyPolicy.activity(in:id,now:Date())
                }
            }
            return event
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            lockObservers.append(workspace.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.lockAllPrivateSpaces() } })
        }
        lockObservers.append(DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.apple.screenIsLocked"),object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.lockAllPrivateSpaces() } })
        synchronizePrivacy()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.maintenance() } }
        maintenance()
    }
    func expirePrivateSpaces() {
        guard !privacyPolicy.grants.isEmpty else { return }
        if !privacyPolicy.expire(now:Date()).isEmpty { synchronizePrivacy() }
    }
    func synchronizePrivacy() {
        github.suspend(except: locked ? nil : space.id)
        for s in state.spaces where isLocked(s.id) { github.purge(s.id) }
        for s in state.spaces where s.privacy != nil {
            s.profileID.uuidString.withCString { AavaEngineLockProfile($0,isLocked(s.id)) }
        }
        if locked {
            linkChoices.clear()
            notifications.clear()
            address = ""; findText = ""; showSearch = false; showFind = false; showSettings = false
            dismissPanels()
        }
        let blocked = prompts.filter { prompt in !state.spaces.contains { $0.profileID.uuidString == prompt.profile && !isLocked($0.id) } }
        for prompt in blocked { resolvePrompt(prompt, allow: false) }
        reconcileCalls()
        objectWillChange.send()
    }
    func lockAllPrivateSpaces() { privacyPolicy.lockAll(); privateError = nil; synchronizePrivacy() }
    func lockCurrentSpace() { privacyPolicy.lock(space.id); privateError = nil; synchronizePrivacy() }
    func unlockPrivateSpace(pin: String, stayOn: Bool, minutes: Int) {
        guard space.privacy != nil else { return }
        do {
            try vault.verify(space.id,pin:pin)
            privacyPolicy.unlock(space.id,stayOn:stayOn,minutes:minutes,now:Date())
            state.spaces[state.currentSpaceIndex].privacy = PrivateSpaceSettings(idleMinutes:minutes, stayOn:stayOn)
            privateError = nil; synchronizePrivacy(); activate(); persist()
        } catch { privateError = error.localizedDescription }
    }
    func beginPrivateSetup() {
        guard !locked, space.privacy == nil else { return }
        privateTarget = space.id; privateDraft = nil; privateError = nil; showSettings = false; showPrivateSetup = true
    }
    func beginPrivateSpace(name: String, emoji: String) {
        let clean = name.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else { return }
        privateDraft = BrowserSpace(name:clean,emoji:emoji.isEmpty ? "🔒" : String(emoji.prefix(1)),theme:.tide)
        privateTarget = privateDraft?.id; privateError = nil; showSettings = false; showPrivateSetup = true
    }
    func finishPrivateSetup(pin: String, confirmation: String) {
        guard mayPersist else { privateError = "Resolve the saved-session error before enabling private spaces."; return }
        guard let id = privateTarget, pin == confirmation else { privateError = "The PINs don’t match."; return }
        do {
            var updated = state
            if let draft = privateDraft { updated.spaces.append(draft) }
            guard let index = updated.spaces.firstIndex(where: { $0.id == id }) else { return }
            guard updated.spaces[index].privacy == nil else { return }
            updated.spaces[index].privacy = PrivateSpaceSettings()
            updated.selectedSpaceID = id
            try vault.replace(id,pin:pin)
            do { try repository.save(updated) }
            catch { try? vault.removeNewRecord(id); throw error }
            if id != space.id { privacyPolicy.leave(space.id) }
            state = updated; privateDraft = nil; privateTarget = nil
            showPrivateSetup = false; privateError = nil
            synchronizePrivacy()
        } catch { privateError = "Private space wasn’t enabled: \(error.localizedDescription)" }
    }
    func privatePreferences(stayOn: Bool, minutes: Int) {
        guard !locked, space.privacy != nil else { return }
        state.spaces[state.currentSpaceIndex].privacy = PrivateSpaceSettings(idleMinutes: minutes, stayOn: stayOn)
        privacyPolicy.unlock(space.id, stayOn: stayOn, minutes: minutes, now: Date()); persist()
    }
    func changePrivatePIN(current: String, new: String, confirmation: String) -> Bool {
        guard !locked, space.privacy != nil, new == confirmation else { return false }
        do { try vault.verify(space.id, pin: current); try vault.replace(space.id, pin: new); privateError = nil; return true }
        catch { privateError = error.localizedDescription; return false }
    }
    func removePrivateLock(pin: String) -> Bool {
        guard !locked, space.privacy != nil, mayPersist else { return false }
        do {
            try vault.verify(space.id, pin: pin)
            var updated = state; updated.spaces[updated.currentSpaceIndex].privacy = nil
            try repository.save(updated)
            let id = space.id; state = updated; privacyPolicy.lock(id)
            try? vault.removeNewRecord(id)
            privateError = nil; synchronizePrivacy(); return true
        } catch { privateError = error.localizedDescription; return false }
    }
    func appearance(transparency: Double? = nil, noise: Double? = nil) {
        guard !locked else { return }
        var value = space.appearance ?? SpaceAppearance()
        if let transparency { value.transparency = transparency }
        if let noise { value.noise = noise }
        state.spaces[state.currentSpaceIndex].appearance = value; persist()
    }
    func importBackground(_ url: URL) {
        guard !locked, mayPersist else { return }
        do { try commitBackground(AavaBackgroundFiles.repository.importFile(url, profile: space.profileID)) }
        catch { backgroundError = error.localizedDescription }
    }
    func importBackground(_ data: Data, name: String) {
        guard !locked, mayPersist else { return }
        do { try commitBackground(AavaBackgroundFiles.repository.importData(data, name: name, profile: space.profileID)) }
        catch { backgroundError = error.localizedDescription }
    }
    private func commitBackground(_ asset: BackgroundAsset) throws {
        let old = space.appearance?.background
        var updated = state, appearance = space.appearance ?? SpaceAppearance(); appearance.background = asset
        updated.spaces[updated.currentSpaceIndex].appearance = appearance
        do { try repository.save(updated) } catch { AavaBackgroundFiles.repository.remove(asset, profile: space.profileID); throw error }
        state = updated; backgroundError = nil
        if let old { AavaBackgroundFiles.repository.remove(old, profile: space.profileID) }
    }
    func removeBackground() {
        guard !locked, mayPersist else { return }
        let old = space.appearance?.background
        var updated = state, appearance = space.appearance ?? SpaceAppearance(); appearance.background = nil
        updated.spaces[updated.currentSpaceIndex].appearance = appearance
        do {
            try repository.save(updated); state = updated; backgroundError = nil
            if let old { AavaBackgroundFiles.repository.remove(old, profile: space.profileID) }
        } catch { backgroundError = error.localizedDescription }
    }
    func pasteBackground(_ pasteboard: NSPasteboard) -> Bool {
        guard !locked else { return false }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first {
            importBackground(url); return true
        }
        for type in [NSPasteboard.PasteboardType("com.compuserve.gif"), .png, .tiff] {
            if let data = pasteboard.data(forType: type) { importBackground(data, name: type.rawValue.contains("gif") ? "Pasted GIF" : "Pasted image"); return true }
        }
        backgroundError = "Copy an image or image file, then paste here."; return true
    }
    func previewArcImport() { openPanel(.importSource) }
    func loadArcImport(path: String) {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        do {
            let file = URL(fileURLWithPath: expanded)
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 50 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: file)
            let preview = try ArcImporter.read(data)
            dismissPanels(); importPreview = preview
        } catch { message = "Could not read the Arc sidebar: \(error.localizedDescription)" }
    }
    func commitArcImport(selected: Set<UUID>) {
        guard mayPersist else { message = "Resolve the saved-session error before importing."; return }
        guard let preview = importPreview else { return }
        let existing = Set(state.spaces.compactMap(\.arcSourceID))
        let additions = preview.spaces.filter { selected.contains($0.id) && !existing.contains($0.arcSourceID ?? "") }
        guard !additions.isEmpty else { importPreview = nil; return }
        do {
            let backup = repository.fileURL.deletingLastPathComponent().appendingPathComponent("Backups/session-before-arc-" + UUID().uuidString + ".json")
            try StateRepository(fileURL:backup).save(state)
            var updated = state; updated.spaces.append(contentsOf:additions); updated.normalize()
            try repository.save(updated)
            state = updated; importPreview = nil
            if showOnboarding {
                onboardingImportedCount += additions.count
                if let first = additions.first { switchSpace(first.id) }
            } else {
                notifications.show("\(additions.count) spaces imported", detail: "Your sidebar is ready.", scope: space.id)
            }
        } catch { message = "Import wasn’t saved: \(error.localizedDescription)" }
    }
    func commitArcProfile(_ addition: BrowserSpace) throws {
        guard mayPersist else { throw ArcMigration.Failure.cannotSave }
        let backup = repository.fileURL.deletingLastPathComponent().appendingPathComponent("Backups/session-before-arc-" + UUID().uuidString + ".json")
        try StateRepository(fileURL: backup).save(state)
        var updated = state
        updated.spaces.append(addition); updated.normalize()
        try repository.save(updated)
        state = updated
    }
    func persist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { self?.saveNow() }
        }
    }
    func saveNow() {
        guard mayPersist else { return }
        do { try repository.save(state) } catch { message = "Session could not be saved: \(error.localizedDescription)" }
    }
    func container(for id: UUID) -> NSView {
        if let view = views[id] { return view }
        let view = PageAnchor(tabID: id, frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        view.autoresizingMask = [.width, .height]
        views[id] = view
        return view
    }
    func activate() {
        guard !locked, !showOnboarding else { return }
        github.refresh(space: space)
        loading = false; canBack = false; canForward = false
        guard let tab, let url = tab.url, !loaded.contains(tab.id), !closing.contains(tab.id), !sleeping.contains(tab.id) else {
            if let tab { action("status", id: tab.id) }; return
        }
        let view = container(for: tab.id)
        loaded.insert(tab.id)
        tab.id.uuidString.withCString { tid in space.profileID.uuidString.withCString { profile in url.absoluteString.withCString { location in
            AavaEngineCreate(Unmanaged.passUnretained(view).toOpaque(), tid, profile, location)
        } } }
    }
    func switchSpace(_ id: UUID, direction: Int? = nil) {
        guard id != space.id, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return }
        let probe = SpaceSwitchMetrics.begin(); defer { SpaceSwitchMetrics.end(probe) }
        spaceDirection = direction ?? (index > state.currentSpaceIndex ? 1 : -1)
        linkChoices.clear()
        backgroundError = nil; notifications.clear(); dismissPanels()
        showSearch = false; showFind = false
        privacyPolicy.leave(space.id)
        state.selectedSpaceID = id; privateError = nil
        synchronizePrivacy()
        // Present the new space immediately; cold Chromium creation and service
        // refresh run after the initial feedback, and rapid switches cancel them.
        spaceActivation?.cancel()
        if let tab, loaded.contains(tab.id) { action("status", id: tab.id) }
        else { loading = false; canBack = false; canForward = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.space.id == id, !self.locked else { return }
            if let tab = self.tab, self.loaded.contains(tab.id) { self.github.refresh(space: self.space) }
            else { self.activate() }
        }
        spaceActivation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
        persist()
    }
    func stepSpace(_ step: Int) {
        guard let index = SpaceNavigation.destination(current: state.currentSpaceIndex, count: state.spaces.count, step: step) else { return }
        switchSpace(state.spaces[index].id, direction: step > 0 ? 1 : -1)
    }
    func select(_ id: UUID) { guard space.tabs.contains(where: { $0.id == id }), mayAccess(id) else { return }; state.spaces[state.currentSpaceIndex].selectedTabID = id; state.touchTab(id); reconcileCalls(); activate(); persist() }
    func newTab(_ url: URL? = nil) {
        guard !locked else { return }
        guard let url else { launchCommand(newTab: true); return }
        dismissPanels(); showSearch = false; state.addTab(url: url); reconcileCalls(); activate(); persist()
    }
    func search() { launchCommand(newTab: false) }
    func launchCommand(newTab: Bool) {
        guard !locked, prompts.isEmpty else { return }
        dismissPanels(); commandNewTab = newTab; commandIndex = 0
        address = newTab ? "" : currentURL?.absoluteString ?? ""; showSearch = true
    }
    func navigate() {
        guard !locked else { return }
        guard let url = NavigationInput.resolve(address) else { message = "Enter an HTTP or HTTPS address, or a search."; return }
        if commandNewTab { newTab(url); return }
        guard let tab else { return }
        state.updateTab(tab.id, url: url, title: url.host)
        state.touchTab(tab.id)
        showSearch = false
        if loaded.contains(tab.id) {
            tab.id.uuidString.withCString { id in url.absoluteString.withCString { AavaEngineNavigate(id, $0) } }
        } else { activate() }
        persist()
    }
    func external(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if locked, let target = state.spaces.first(where: { $0.privacy == nil }) { switchSpace(target.id) }
        guard !locked else { message = "Unlock a space before opening this link."; return }
        newTab(url)
    }
    func action(_ action: String, id: UUID? = nil) {
        guard let id = id ?? tab?.id, mayAccess(id) || action == "dock" else { return }
        id.uuidString.withCString { tid in action.withCString { AavaEngineAction(tid, $0) } }
    }
    func close(_ id: UUID, reason: ArchiveReason = .closed) {
        guard mayAccess(id) else { return }
        if closing.contains(id) { return }
        pendingArchive[id] = reason
        if panel == .tab(id) { panel = nil }
        if loaded.contains(id) { closing.insert(id); id.uuidString.withCString { AavaEngineClose($0) } }
        else { state.archiveTab(id, reason: reason); pendingArchive[id] = nil; views.removeValue(forKey: id); reconcileCalls(); activate(); saveNow() }
    }
    func sleep(_ id: UUID) { guard mayAccess(id), loaded.contains(id) else { return }; openPanel(.sleep(id)) }
    func confirmSleep(_ id: UUID) {
        guard mayAccess(id), loaded.contains(id), !callPolicy.capturing.contains(id) else { return }
        dismissPanels(); sleeping.insert(id); id.uuidString.withCString { AavaEngineClose($0) }
    }
    func wake() { activate(); objectWillChange.send() }
    func isSleeping(_ id: UUID) -> Bool { !loaded.contains(id) && state.spaces.contains { $0.tabs.contains { $0.id == id && $0.url != nil } } }
    func pin(_ id: UUID) {
        guard mayAccess(id) else { return }
        guard let i = space.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.spaces[state.currentSpaceIndex].tabs[i].pinned.toggle(); state.spaces[state.currentSpaceIndex].tabs[i].pinnedURL = state.spaces[state.currentSpaceIndex].tabs[i].pinned ? space.tabs[i].url : nil; persist()
    }
    func tileStyle(_ id: UUID, _ style: PinnedTileStyle) {
        guard !locked, let index = space.tabs.firstIndex(where: { $0.id == id && $0.pinned }) else { return }
        var value = style
        value.span = style.columns; value.tint = style.validTint
        value.name = style.name.map { String($0.prefix(80)) }
        state.spaces[state.currentSpaceIndex].tabs[index].tile = value; persist()
    }
    func faviconTint(_ url: URL?) -> String {
        locked ? FaviconTint.fallback : faviconCache.tint(url, profile: space.profileID)
    }
    func copyURL() {
        guard let url = currentURL else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
        notifications.show("Link copied", detail: "Ready to paste.", scope: space.id)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }
    func savePage(parent: UUID? = nil) {
        guard let tab, let url = tab.url else { return }
        guard mayPersist else { message = "Resolve the saved-session error before saving pages."; return }
        var updated = state
        updated.spaces[updated.currentSpaceIndex].saved.append(SavedItem(title: tab.title, url: url, parentID: parent))
        do {
            try repository.save(updated); state = updated
            notifications.show("Page saved", detail: "Ready in your sidebar.", scope: space.id)
        } catch { message = "Page couldn’t be saved: \(error.localizedDescription)" }
    }
    func addFolder(parent: UUID? = nil) { guard !locked else { return }; openPanel(.folder(parent)) }
    func createFolder(title: String, parent: UUID?) {
        guard !locked else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, parent == nil || space.saved.contains(where: { $0.id == parent && $0.isFolder }) else { return }
        state.spaces[state.currentSpaceIndex].saved.append(SavedItem(title: String(clean.prefix(200)), parentID: parent))
        if let parent { state.spaces[state.currentSpaceIndex].collapsedFolderIDs?.remove(parent) }
        dismissPanels(); persist()
    }
    func toggleFolder(_ id: UUID) { guard !locked else { return }; state.toggleFolder(id); persist() }
    func renameSaved(_ id: UUID, title: String) { guard !locked else { return }; if state.renameSaved(id, title: title) { persist() } }
    func moveSaved(_ id: UUID, parent: UUID?) { guard !locked else { return }; if state.moveSaved(id, to: parent) { persist() } }
    func renameSpace(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !locked, !clean.isEmpty else { return }
        state.spaces[state.currentSpaceIndex].name = String(clean.prefix(80)); persist()
    }
    func deleteSaved(_ id: UUID) { guard !locked else { return }; state.deleteSaved(id); persist() }
    func liquidGlass(_ enabled: Bool) { guard !locked else { return }; state.spaces[state.currentSpaceIndex].liquidGlass = enabled; persist() }
    func theme(_ theme: SpaceTheme) { guard !locked else { return }; state.spaces[state.currentSpaceIndex].theme = theme; persist() }
    func icons(_ icons: IconStyle) { guard !locked else { return }; state.spaces[state.currentSpaceIndex].iconStyle = icons; persist() }
    func addSpace(name: String, emoji: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }
        let s = BrowserSpace(name: clean, emoji: emoji.isEmpty ? "◌" : String(emoji.prefix(1)), theme: .tide)
        state.spaces.append(s); switchSpace(s.id)
    }
    func reconcileCalls() {
        let urls = Dictionary(uniqueKeysWithValues: state.spaces.filter { !isLocked($0.id) }.flatMap(\.tabs).compactMap { tab in tab.url.map { (tab.id, $0) } })
        for transition in callPolicy.reconcile(selected: tab?.id, urls: urls) {
            switch transition {
            case .float(let id): action("popout", id: id)
            case .dock(let id): action("dock", id: id)
            }
        }
    }
    func pinCall(_ id: UUID) { callPolicy.pin(id, enabled: !callPolicy.manual.contains(id)); reconcileCalls() }
    func autoPopouts(_ enabled: Bool) { callPolicy.enabled = enabled; reconcileCalls() }
    func selectFromPopout(_ id: UUID) {
        guard let space = state.spaces.first(where: { $0.tabs.contains(where: { $0.id == id }) }) else { return }
        switchSpace(space.id); if !locked { select(id) }
    }
    func extensions() { guard !locked else { return }; dismissPanels(); newTab(URL(string: "chrome://extensions/")) }
    func downloads() { guard !locked else { return }; openPanel(.downloads) }
    func setDefault() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https") { [weak self] error in
            DispatchQueue.main.async {
                if let error { self?.message = error.localizedDescription; return }
                NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let error { self.message = error.localizedDescription }
                        else { self.notifications.show("Aava is your default browser", scope: self.space.id) }
                    }
                }
            }
        }
    }
    var commandResults: [CommandResult] { locked ? [] : CommandSearch.results(query: address, in: space) }
    func moveCommand(_ step: Int) { let count = commandResults.count; if count > 0 { commandIndex = (commandIndex + step + count) % count } }
    func commitCommand(_ result: CommandResult? = nil) {
        guard !locked else { return }
        let results = commandResults
        guard let result = result ?? (results.indices.contains(commandIndex) ? results[commandIndex] : nil) else { navigate(); return }
        let key = String(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80)) + "|" + result.id
        var selections = space.commandSelections ?? [:]
        if selections.count > 500 { selections.removeAll() }
        selections[key] = min(5, (selections[key] ?? 0) + 1)
        state.spaces[state.currentSpaceIndex].commandSelections = selections
        showSearch = false
        switch result.kind {
        case .tab: if let id = result.target { select(id) }
        case .archive: if let id = result.target { restoreArchived(id) }
        case .saved, .history, .navigate:
            if let url = result.url { address = url.absoluteString; navigate() }
        case .action:
            switch result.id {
            case "library": openLibrary()
            case "tidy": tidyTabs()
            case "clean": openPanel(.cleanup)
            case "settings": openSettings()
            case "github": openPanel(.github)
            case "extensions": extensions()
            case "downloads": downloads()
            case "pin": if let id = tab?.id { pin(id) }
            case "reset-pin": resetPinned()
            case "copy": copyURL()
            case "save": savePage()
            case "folder": addFolder()
            case "space": openSettings("Spaces")
            case "pip": action("pip")
            case "devtools": action("devtools")
            case "import": previewArcImport()
            case "lock": lockAllPrivateSpaces()
            default: break
            }
        }
        persist()
    }
    func openURL(_ url: URL) {
        guard !locked else { return }
        dismissPanels(); showSearch = false
        if let existing = space.tabs.first(where: { $0.url == url }) { select(existing.id) }
        else { newTab(url) }
    }
    func resetPinned(_ id: UUID? = nil) {
        guard !locked, let tab = space.tabs.first(where: { $0.id == (id ?? self.tab?.id) }), let url = tab.pinnedURL, tab.pinned else { return }
        select(tab.id); commandNewTab = false; address = url.absoluteString; navigate()
    }
    func openLibrary(_ section: String = "History") { guard !locked else { return }; librarySection = section; openPanel(.library) }
    func restoreArchived(_ id: UUID) {
        guard !locked, state.restoreArchive(id) != nil else { return }
        dismissPanels(); showSearch = false; reconcileCalls(); activate(); saveNow()
    }
    func reopenLastClosed() { guard !locked, let id = space.archive?.first?.id else { return }; restoreArchived(id) }
    func clearLibrary(_ archive: Bool) {
        guard !locked else { return }
        if archive { state.spaces[state.currentSpaceIndex].archive = [] }
        else { state.spaces[state.currentSpaceIndex].history = []; state.spaces[state.currentSpaceIndex].commandSelections = [:] }
        saveNow()
    }
    var protectedTabs: Set<UUID> { callPolicy.capturing.union(callPolicy.manual).union(callPolicy.floating).union(callPolicy.sitePopouts).union(activeDownloads).union(closing).union(sleeping) }
    var cleanupCandidates: [UUID] { locked ? [] : TabCleanup.cleanable(in: space, protected: protectedTabs) }
    func tidyTabs() {
        guard !locked else { return }; state.tidyTabs(); persist()
        notifications.show("Tabs tidied", detail: "Grouped by website. No pages closed.", scope: space.id)
    }
    func cleanTabs(all: Bool = false) {
        guard !locked else { return }
        let ids = all ? space.tabs.filter { !$0.pinned && $0.id != space.selectedTabID && !protectedTabs.contains($0.id) }.map(\.id) : cleanupCandidates
        dismissPanels()
        for id in ids { safeArchive(id, reason: .clean) }
        notifications.show("Cleanup started", detail: "Recover closed pages in Library → Archive. Pages with unsaved-change warnings stay open.", scope: space.id)
    }
    private func safeArchive(_ id: UUID, reason: ArchiveReason) {
        guard mayAccess(id), !protectedTabs.contains(id), id != tab?.id else { return }
        if loaded.contains(id) {
            closing.insert(id); pendingArchive[id] = reason
            id.uuidString.withCString { AavaEngineArchive($0) }
        } else { close(id, reason: reason) }
    }
    func autoArchive(_ hours: Int) { guard !locked else { return }; state.spaces[state.currentSpaceIndex].autoArchiveHours = hours; persist() }
    func maintenance() {
        guard !locked, !showOnboarding else { return }
        if let id = tab?.id { state.touchTab(id); persist() }
        if !hasPanel && !showSearch { for id in TabCleanup.expired(in: space, now: Date(), protected: protectedTabs) { safeArchive(id, reason: .automatic) } }
        github.refresh(space: space)
    }
    func connectGitHub(token: String, configuration: GitHubFolderConfiguration) {
        guard !locked else { return }; let scope = space.id
        github.connect(space: space, token: token, configuration: configuration) { [weak self] config in
            guard let self, !isLocked(scope), let i = state.spaces.firstIndex(where: { $0.id == scope }) else { return }
            state.spaces[i].githubFolder = config; persist()
        }
    }
    func disconnectGitHub() {
        guard !locked else { return }
        do { try github.disconnect(space: space); state.spaces[state.currentSpaceIndex].githubFolder = nil; persist() }
        catch { message = error.localizedDescription }
    }
    func toggleGitHubRepo(_ repo: String) {
        guard !locked, var config = space.githubFolder else { return }
        if !config.collapsedRepositories.insert(repo).inserted { config.collapsedRepositories.remove(repo) }
        state.spaces[state.currentSpaceIndex].githubFolder = config; persist()
    }
    func event(id: String, name: String, value: String) {
        if name == "arc-cookies" { arcMigration.cookieResult(token: id, json: value, store: self); return }
        if name == "download-state", let data = value.data(using: .utf8), let download = try? JSONDecoder().decode(BrowserDownload.self, from: data) {
            let fresh = !(state.spaces.first(where: { $0.profileID == download.profile })?.downloads ?? []).contains { $0.id == download.id }
            let completed = state.updateDownload(download)
            if download.profile == space.profileID && !locked {
                if fresh { downloadTrayExpanded = true }
                if completed { notifications.show("Download saved", detail: download.name, scope: space.id) }
            }
            persist(); return
        }
        if name == "prompt", let data = value.data(using: .utf8), let prompt = try? JSONDecoder().decode(AavaPrompt.self, from: data) {
            guard prompts.count < 8, state.spaces.contains(where: { $0.profileID.uuidString == prompt.profile && !isLocked($0.id) }) else { resolvePrompt(prompt, allow: false); return }
            showSearch = false; prompts.append(prompt); AavaFocus(); return
        }
        if name == "prompt-cancelled" { prompts.removeAll { $0.token == value }; return }
        if name == "favicon", let uuid = UUID(uuidString: id), mayAccess(uuid),
           let owner = state.spaces.first(where: { $0.tabs.contains { $0.id == uuid } }),
           let data = value.data(using: .utf8), let payload = try? JSONDecoder().decode(FaviconPayload.self, from: data),
           let url = URL(string: payload.page), let image = Data(base64Encoded: payload.png) {
            faviconCache.save(image, url: url, profile: owner.profileID); objectWillChange.send(); return
        }

        if name == "copied", let uuid = UUID(uuidString: id), mayAccess(uuid), space.tabs.contains(where: { $0.id == uuid }) {
            notifications.show("Link copied", detail: "Ready to paste.", scope: space.id); return
        }
        if name == "download-complete", let uuid = UUID(uuidString: id), mayAccess(uuid), space.tabs.contains(where: { $0.id == uuid }) {
            notifications.show("Download saved", detail: "Find it in Downloads.", scope: space.id); return
        }
        if name == "error" { if let uuid = UUID(uuidString:id), mayAccess(uuid) { message = value }; return }
        guard let id = UUID(uuidString: id) else { return }
        switch name {
        case "url": state.updateTab(id, url: URL(string: value), title: nil); reconcileCalls(); persist()
        case "title":
            state.updateTab(id, url: nil, title: value)
            if let i = state.spaces.firstIndex(where: { $0.tabs.contains { $0.id == id } }),
               let url = state.spaces[i].tabs.first(where: { $0.id == id })?.url,
               let j = state.spaces[i].history?.firstIndex(where: { $0.url == url }) { state.spaces[i].history?[j].title = value }
            persist()
        case "visited": if mayAccess(id), let url = URL(string: value) { state.recordVisit(id, url: url); persist() }
        case "downloading": if value == "1" { activeDownloads.insert(id) } else { activeDownloads.remove(id) }
        case "status":
            if id == tab?.id { let parts = value.split(separator: ","); if parts.count == 3 { loading = parts[0] == "1"; canBack = parts[1] == "1"; canForward = parts[2] == "1" } }
        case "search": selectFromPopout(id); search()
        case "site-pip": callPolicy.sitePopout(id, active: value == "1"); reconcileCalls()
        case "request-close": close(id)
        case "capture": callPolicy.media(id, active: value == "1"); reconcileCalls()
        case "select": selectFromPopout(id)
        case "closed":
            callPolicy.remove(id)
            loaded.remove(id); views.removeValue(forKey: id)
            if closing.remove(id) != nil { state.archiveTab(id, reason: pendingArchive.removeValue(forKey: id) ?? .closed); reconcileCalls(); activate(); saveNow() }
            activeDownloads.remove(id)
            sleeping.remove(id); persist(); objectWillChange.send()
        case "close-cancelled": closing.remove(id); sleeping.remove(id); pendingArchive[id] = nil; state.touchTab(id); persist()
        default: break
        }
    }
}

@MainActor final class PageAnchor: NSView {
    let tabID: UUID
    init(tabID: UUID, frame: NSRect) { self.tabID = tabID; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func sync() { let start = CFAbsoluteTimeGetCurrent(); tabID.uuidString.withCString { AavaEngineSync($0) }; SpaceSwitchMetrics.pageSyncs += 1; SpaceSwitchMetrics.pageMilliseconds += (CFAbsoluteTimeGetCurrent() - start) * 1000 }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); sync() }
    override func layout() { super.layout(); sync() }
    override func setFrameSize(_ size: NSSize) { super.setFrameSize(size); sync() }
    override func setFrameOrigin(_ point: NSPoint) { super.setFrameOrigin(point); sync() }
}

// Opt-in local QA measurements: no URLs, names or browsing content are recorded.
@MainActor enum SpaceSwitchMetrics {
    static var pageSyncs = 0
    static var surfaceSyncs = 0
    static var pageMilliseconds = 0.0
    struct Sample { let start: Double; let pages: Int; let surfaces: Int; let pageMS: Double }
    static func begin() -> Sample? {
        guard ProcessInfo.processInfo.environment["AAVA_SPACE_METRICS"] != nil else { return nil }
        return Sample(start: CFAbsoluteTimeGetCurrent(), pages: pageSyncs, surfaces: surfaceSyncs, pageMS: pageMilliseconds)
    }
    static func end(_ sample: Sample?) {
        guard let sample, let path = ProcessInfo.processInfo.environment["AAVA_SPACE_METRICS"] else { return }
        let synchronous = (CFAbsoluteTimeGetCurrent() - sample.start) * 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let record: [String: Any] = ["switchMS": synchronous, "pageSyncs": pageSyncs - sample.pages, "pageSyncMS": pageMilliseconds - sample.pageMS, "surfaceSyncs": surfaceSyncs - sample.surfaces]
            guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
            DispatchQueue.global(qos: .utility).async {
                if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
                if let file = FileHandle(forWritingAtPath: path) { defer { try? file.close() }; file.seekToEndOfFile(); file.write(data + Data([10])) }
            }
        }
    }
}
