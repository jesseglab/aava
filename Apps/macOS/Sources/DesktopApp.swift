import AppKit
import SwiftUI

@MainActor private var coordinator: DesktopCoordinator?

@_cdecl("AavaStart")
public func startAava() {
    MainActor.assumeIsolated {
        let app = DesktopCoordinator()
        coordinator = app
        app.start()
    }
}
@_cdecl("AavaFocus")
public func focusAava() { MainActor.assumeIsolated { coordinator?.showWindow() } }

@_cdecl("AavaOfferLinkChoice")
public func offerAavaLinkChoice(_ tab: UnsafePointer<CChar>?, _ source: UnsafePointer<CChar>?, _ target: UnsafePointer<CChar>?) -> Bool {
    guard let tab, let source, let target else { return false }
    return MainActor.assumeIsolated {
        coordinator?.store.offerLinkChoice(tab: String(cString: tab), source: String(cString: source), target: String(cString: target)) ?? false
    }
}

@_cdecl("AavaCanOfferLinkChoice")
public func canOfferAavaLinkChoice(_ tab: UnsafePointer<CChar>?, _ source: UnsafePointer<CChar>?, _ target: UnsafePointer<CChar>?) -> Bool {
    guard let tab, let source, let target else { return false }
    return MainActor.assumeIsolated {
        coordinator?.store.linkCandidate(tab: String(cString: tab), source: String(cString: source), target: String(cString: target)) != nil
    }
}

@_cdecl("AavaDismissSurface")
public func dismissAavaSurface() -> Bool {
    MainActor.assumeIsolated {
        guard let store = coordinator?.store else { return false }
        if store.linkChoices.request != nil { store.linkChoices.clear(); return true }
        guard store.hasPanel else { return false }
        if let prompt = store.prompts.first { store.resolvePrompt(prompt, allow: false) }
        else { store.dismissPanels() }
        return true
    }
}

@MainActor final class DesktopCoordinator: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = MacStore()
    var window: NSWindow!
    var surfaces: AavaSurfaces?
    func start() {
        NSApplication.shared.delegate = self
        NSApplication.shared.setActivationPolicy(.regular)
        if let icon = AavaBrand.appIcon { NSApplication.shared.applicationIconImage = icon }
        AavaEngineSetCallback { id, name, value in
            let identifier = String(cString: id!), event = String(cString: name!), data = String(cString: value!)
            DispatchQueue.main.async { coordinator?.store.event(id: identifier, name: event, value: data) }
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Aava"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true; window.minSize = NSSize(width: 800, height: 540)
        window.backgroundColor = .clear; window.isOpaque = false; window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AavaRootView(store: store).ignoresSafeArea())
        window.setFrameAutosaveName("AavaMainWindow")
        window.center()
        store.startPrivacyMonitoring()
        makeMenu()
        showWindow()
        surfaces = AavaSurfaces(parent: window, store: store)
        for arg in CommandLine.arguments.dropFirst() where arg.hasPrefix("https://") || arg.hasPrefix("http://") { if let url = URL(string: arg) { store.external(url) } }
    }
    func showWindow() { window?.makeKeyAndOrderFront(nil); positionWindowControls(); NSApp.activate(ignoringOtherApps: true); surfaces?.sync() }
    func windowDidResize(_ notification: Notification) { positionWindowControls() }
    func windowDidUpdate(_ notification: Notification) { positionWindowControls() }
    func windowDidExitFullScreen(_ notification: Notification) { positionWindowControls() }
    private func positionWindowControls() {
        guard let window, !window.styleMask.contains(.fullScreen), let content = window.contentView,
              let close = window.standardWindowButton(.closeButton), let titlebar = close.superview,
              let container = titlebar.superview else { return }
        let height = AavaGeometry.trafficLightCenterY + close.frame.height / 2 + 8
        // Keep the native titlebar hit area around the lowered system buttons.
        // Moving only the buttons would leave their lower halves unclickable.
        if container.frame.height < height {
            var frame = container.frame; frame.origin.y = frame.maxY - height; frame.size.height = height
            container.frame = frame
        }
        if titlebar.frame.height < height { titlebar.setFrameSize(NSSize(width: titlebar.frame.width, height: height)) }
        let gap: CGFloat = 23
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            let x = AavaGeometry.frameInset + AavaGeometry.sidebarInset + CGFloat(index) * gap
            let y = content.isFlipped ? AavaGeometry.trafficLightCenterY - button.frame.height / 2 : content.bounds.height - AavaGeometry.trafficLightCenterY - button.frame.height / 2
            let rect = content.convert(NSRect(x: x, y: y, width: button.frame.width, height: button.frame.height), to: parent)
            if button.frame.origin != rect.origin { button.setFrameOrigin(rect.origin) }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) { showWindow(); urls.forEach(store.external) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { store.lockAllPrivateSpaces(); store.saveNow(); sender.orderOut(nil); return false }
    @objc func quit() { store.saveNow(); MiniControl.shared.stopForQuit { AavaEngineQuit() } }
    @objc func newTab() { showWindow(); store.newTab() }
    @objc func search() { showWindow(); store.search() }
    @objc func closeTab() { if AavaEngineCloseFocused() { return }; if let id = store.tab?.id { store.close(id) } }
    @objc func library() { showWindow(); store.openLibrary() }
    @objc func reopenTab() { store.reopenLastClosed() }
    @objc func cleanup() { store.openPanel(.cleanup) }
    @objc func githubFolder() { store.openPanel(.github) }
    @objc func reload() { store.action("reload") }
    @objc func back() { store.action("back") }
    @objc func forward() { store.action("forward") }
    @objc func settings() { if !store.locked && !store.showOnboarding { store.openSettings() } }
    @objc func mini() { MiniControl.shared.show() }
    @objc func welcome() { showWindow(); store.replayOnboarding() }
    @objc func about() { store.showAbout = true }
    @objc func nextSpace() { store.stepSpace(1) }
    @objc func previousSpace() { store.stepSpace(-1) }
    @objc func savePage() { store.savePage() }
    @objc func copyURL() { store.copyURL() }
    @objc func find() { if !store.locked { store.showFind.toggle() } }
    @objc func zoomIn() { store.action("zoom-in") }
    @objc func zoomOut() { store.action("zoom-out") }
    @objc func zoomReset() { store.action("zoom-reset") }
    @objc func extensions() { store.extensions() }
    @objc func importArc() { store.previewArcImport() }
    @objc func lockPrivate() { store.lockAllPrivateSpaces() }
    @objc func downloads() { store.downloads() }
    @objc func pip() { store.action("pip") }
    @objc func defaultBrowser() { store.setDefault() }
    @objc func devtools() { store.action("devtools") }
    private func makeMenu() {
        let bar = NSMenu()
        func group(_ title: String) -> NSMenu { let item = NSMenuItem(); let menu = NSMenu(title: title); item.submenu = menu; bar.addItem(item); return menu }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = target ?? self; entry.keyEquivalentModifierMask = modifiers; menu.addItem(entry)
        }
        let app = group("Aava")
        item(app, "About Aava", #selector(about))
        app.addItem(.separator())
        item(app, "Customize Space…", #selector(settings), ",")
        item(app, "Make Aava Default Browser…", #selector(defaultBrowser))
        app.addItem(.separator())
        item(app, "Hide Aava", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(app, "Quit Aava", #selector(quit), "q")
        let file = group("File")
        item(file, "Import from Arc…", #selector(importArc))
        item(file, "Lock Private Spaces", #selector(lockPrivate), "l", modifiers: [.command, .shift])
        file.addItem(.separator())
        item(file, "New Tab", #selector(newTab), "t")
        item(file, "Open Location…", #selector(search), "l")
        item(file, "Reopen Closed Tab", #selector(reopenTab), "t", modifiers: [.command, .shift])
        item(file, "Close Tab", #selector(closeTab), "w")
        item(file, "Save Page to Sidebar", #selector(savePage), "d")
        let edit = group("Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            let entry = NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key); edit.addItem(entry)
        }
        item(edit, "Find…", #selector(find), "f")
        let view = group("View")
        item(view, "Reload", #selector(reload), "r")
        item(view, "Zoom In", #selector(zoomIn), "+")
        item(view, "Zoom Out", #selector(zoomOut), "-")
        item(view, "Actual Size", #selector(zoomReset), "0")
        item(view, "Picture in Picture", #selector(pip))
        item(view, "Developer Tools", #selector(devtools), "i", modifiers: [.command, .option])
        let history = group("Navigate")
        item(history, "History and Archive", #selector(library), "y")
        item(history, "Back", #selector(back), "[")
        item(history, "Forward", #selector(forward), "]")
        item(history, "Next Space", #selector(nextSpace), String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: [.command, .option])
        item(history, "Previous Space", #selector(previousSpace), String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [.command, .option])
        item(history, "Copy URL", #selector(copyURL), "c", modifiers: [.command, .shift])
        let tools = group("Tools")
        item(tools, "Tidy Up and Clean Tabs…", #selector(cleanup))
        item(tools, "GitHub Live Folder…", #selector(githubFolder))
        item(tools, "Extensions…", #selector(extensions))
        item(tools, "Downloads", #selector(downloads))
        let help = group("Help")
        item(tools, "Mini AI Workspace…", #selector(mini))
        item(help, "Welcome to Aava…", #selector(welcome))
        NSApp.mainMenu = bar
    }
}
