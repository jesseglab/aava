import AavaCore
import SwiftUI
import WebKit

@MainActor final class BrowserStore: NSObject, ObservableObject {
    @Published var state: BrowserState
    @Published var activeWebView: WKWebView?
    @Published var loading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    @Published var downloads: [URL] = []
    @Published var shareURL: URL?
    @Published var addressRequested = false

    private let repository: StateRepository
    private var mayPersist = true
    private var views: [UUID: WKWebView] = [:]
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var downloadsInProgress: [ObjectIdentifier: (WKDownload, URL?)] = [:]
    private var persistenceTask: Task<Void, Never>?

    var space: BrowserSpace { state.currentSpace }
    var currentTab: BrowserTab? { state.currentTab }
    var currentURL: URL? { activeWebView?.url ?? currentTab?.url }

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aava", isDirectory: true)
        repository = StateRepository(fileURL: base.appendingPathComponent("browser-state.json"))
        var loadError: String?
        do { state = try repository.load() }
        catch {
            state = BrowserState(); mayPersist = false
            loadError = "Your saved session could not be read. It has been left untouched. This session will not overwrite it."
        }
        super.init()
        errorMessage = loadError
        refreshDownloads()
        activateCurrent()
    }

    func saveNow() {
        guard mayPersist else { return }
        do { try repository.save(state) }
        catch { errorMessage = "Aava could not save your session: \(error.localizedDescription)" }
    }
    func persist() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
    func switchSpace(_ id: UUID) {
        guard state.spaces.contains(where: { $0.id == id }) else { return }
        state.selectedSpaceID = id; activateCurrent(); persist()
    }
    func stepSpace(_ delta: Int) {
        let count = state.spaces.count
        switchSpace(state.spaces[(state.currentSpaceIndex + delta + count) % count].id)
    }
    func selectTab(_ id: UUID) {
        guard space.tabs.contains(where: { $0.id == id }) else { return }
        state.spaces[state.currentSpaceIndex].selectedTabID = id
        activateCurrent(); persist()
    }
    func newTab(url: URL? = nil) {
        state.addTab(url: url); activateCurrent(); persist()
    }
    func closeTab(_ id: UUID) {
        views[id]?.stopLoading(); views[id]?.navigationDelegate = nil; views[id]?.uiDelegate = nil
        views.removeValue(forKey: id); observations.removeValue(forKey: id)
        state.closeTab(id); activateCurrent(); persist()
    }
    func togglePin(_ id: UUID) {
        guard let index = space.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.spaces[state.currentSpaceIndex].tabs[index].pinned.toggle(); persist()
    }
    func navigate(_ input: String) {
        guard let url = NavigationInput.resolve(input) else {
            errorMessage = "Enter a website address or a search. Only HTTP and HTTPS pages are supported."; return
        }
        if currentTab == nil { state.addTab() }
        guard let id = currentTab?.id else { return }
        state.updateTab(id, url: url, title: url.host)
        let view = ensureView(for: id)
        activeWebView = view; view.load(URLRequest(url: url)); persist()
    }
    func openExternal(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        newTab(url: url)
    }
    func setTheme(_ theme: SpaceTheme) { state.spaces[state.currentSpaceIndex].theme = theme; persist() }
    func setIconStyle(_ style: IconStyle) { state.spaces[state.currentSpaceIndex].iconStyle = style; persist() }
    func addSpace(name: String, emoji: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let s = BrowserSpace(name: name, emoji: emoji.isEmpty ? "◌" : String(emoji.prefix(2)), theme: .tide)
        state.spaces.append(s); switchSpace(s.id)
    }
    func addFolder(_ title: String, parent: UUID? = nil) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        state.spaces[state.currentSpaceIndex].saved.append(SavedItem(title: clean, parentID: parent)); persist()
    }
    func savePage(parent: UUID? = nil) {
        guard let url = currentURL else { return }
        let item = SavedItem(title: activeWebView?.title ?? currentTab?.title ?? url.host ?? "Saved page", url: url, parentID: parent)
        state.spaces[state.currentSpaceIndex].saved.append(item); persist()
    }
    func removeSaved(_ id: UUID) { state.deleteSaved(id); persist() }
    func copyURL() { if let url = currentURL { UIPasteboard.general.url = url } }
    func back() { activeWebView?.goBack() }
    func forward() { activeWebView?.goForward() }
    func reloadOrStop() { if loading { activeWebView?.stopLoading() } else { activeWebView?.reload() } }

    private func activateCurrent() {
        if let tab = currentTab, tab.url != nil {
            let wasLoaded = views[tab.id] != nil
            let view = ensureView(for: tab.id); activeWebView = view
            if !wasLoaded, let url = tab.url { view.load(URLRequest(url: url)) }
        } else { activeWebView = nil }
        updateActiveMetrics()
    }
    private func ensureView(for id: UUID, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let view = views[id] { return view }
        let config = configuration ?? WKWebViewConfiguration()
        let owner = state.spaces.first { $0.tabs.contains { $0.id == id } } ?? space
        if configuration == nil { config.websiteDataStore = WKWebsiteDataStore(forIdentifier: owner.profileID) }
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self; view.uiDelegate = self
        view.isOpaque = false; view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        #if DEBUG
        view.isInspectable = true
        #endif
        views[id] = view
        observations[id] = [
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.updateActiveMetrics() } },
            view.observe(\.isLoading, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.updateActiveMetrics() } },
            view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.updateActiveMetrics() } },
            view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.updateActiveMetrics() } },
            view.observe(\.title, options: [.new]) { [weak self, weak view] _, _ in Task { @MainActor in self?.updateMetadata(view, id: id) } },
            view.observe(\.url, options: [.new]) { [weak self, weak view] _, _ in Task { @MainActor in self?.updateMetadata(view, id: id) } }
        ]
        return view
    }
    private func updateMetadata(_ view: WKWebView?, id: UUID) {
        guard let view else { return }
        state.updateTab(id, url: view.url, title: view.title); persist()
    }
    private func updateActiveMetrics() {
        loading = activeWebView?.isLoading ?? false
        progress = activeWebView?.estimatedProgress ?? 0
        canGoBack = activeWebView?.canGoBack ?? false
        canGoForward = activeWebView?.canGoForward ?? false
    }
    private func present(_ alert: UIAlertController, in view: WKWebView, fallback: () -> Void) {
        guard var controller = view.window?.rootViewController else { fallback(); return }
        while let presented = controller.presentedViewController { controller = presented }
        controller.present(alert, animated: true)
    }
    private var downloadDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
    }
    private func refreshDownloads() {
        downloads = ((try? FileManager.default.contentsOfDirectory(at: downloadDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

extension BrowserStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob"].contains(scheme) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        } else if ["tel", "mailto", "sms"].contains(scheme), navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel); UIApplication.shared.open(url)
        } else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    private func report(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { errorMessage = error.localizedDescription }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === activeWebView { errorMessage = "This page stopped responding. Reload it to continue. Unsaved page changes may have been lost." }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloadsInProgress[ObjectIdentifier(download)] = (download, nil); download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloadsInProgress[ObjectIdentifier(download)] = (download, nil); download.delegate = self
    }
}

extension BrowserStore: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        guard let sourceID = views.first(where: { $0.value === webView })?.key,
              let owner = state.spaces.first(where: { $0.tabs.contains { $0.id == sourceID } }) else { return nil }
        state.selectedSpaceID = owner.id
        let id = state.addTab(url: navigationAction.request.url)
        let view = ensureView(for: id, configuration: configuration)
        activeWebView = view; updateActiveMetrics(); persist(); return view
    }
    func webViewDidClose(_ webView: WKWebView) {
        if let id = views.first(where: { $0.value === webView })?.key { closeTab(id) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.prompt) }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, in: webView, fallback: completionHandler)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, in: webView, fallback: { completionHandler(false) })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert, in: webView, fallback: { completionHandler(nil) })
    }
}

extension BrowserStore: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do {
            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            let leaf = (suggestedFilename as NSString).lastPathComponent
            let name = leaf.isEmpty || leaf == "." || leaf == ".." ? "Download" : leaf
            var url = downloadDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                url = downloadDirectory.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + name)
            }
            downloadsInProgress[ObjectIdentifier(download)] = (download, url)
            completionHandler(url)
        } catch { errorMessage = error.localizedDescription; completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) { downloadsInProgress.removeValue(forKey: ObjectIdentifier(download)); refreshDownloads() }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let (_, url) = downloadsInProgress.removeValue(forKey: ObjectIdentifier(download)), let url { try? FileManager.default.removeItem(at: url) }
        errorMessage = "Download failed: \(error.localizedDescription)"
    }
}
