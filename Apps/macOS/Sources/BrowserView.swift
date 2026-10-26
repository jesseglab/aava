import AppKit
import SwiftUI

struct AavaBrowserView: View {
    @ObservedObject var store: MacStore
    @State private var sidebarVisible = true
    @AppStorage("aava.sidebarWidth") private var savedSidebarWidth = SidebarSizing.defaultWidth
    @State private var liveSidebarWidth: Double?
    @State private var urlHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ink: Color { store.space.theme.darkText ? AavaBrand.deep : AavaBrand.salt }
    var body: some View {
        GeometryReader { geometry in
        let width = SidebarSizing.width(liveSidebarWidth ?? savedSidebarWidth, container: geometry.size.width)
        HStack(spacing: 8) {
            if sidebarVisible { sidebar(width: width, height: geometry.size.height).frame(width: width) }
            ZStack(alignment: .top) {
                Group {
                    if store.locked { PrivateSpaceCover(store: store).id(store.space.id) }
                    else if let tab = store.tab, tab.url != nil {
                        if store.isSleeping(tab.id) {
                            VStack(spacing: 16) {
                                SiteIcon(store: store, url: tab.url)
                                Text(tab.title).font(.system(size: 20, weight: .medium))
                                Text("Resting until you need it.").font(.system(size: 13)).foregroundStyle(AavaBrand.secondary)
                                Button("Wake tab") { store.wake() }.buttonStyle(AavaPrimaryButton())
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AavaBrand.salt).foregroundStyle(AavaBrand.deep)
                        } else { ChromiumSurface(view: store.container(for: tab.id)) }
                    } else { AavaStartPage(store: store) }
                }.clipShape(RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius, style: .continuous))
                if !store.hasPanel {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 8).contentShape(Rectangle()).onHover { if $0 { urlHovered = true } }
                        if !store.locked && (urlHovered || !sidebarVisible) { urlBar.padding(.horizontal, 12).transition(.opacity) }
                    }.onHover { urlHovered = $0 }
                    if store.showFind && !store.locked {
                        HStack {
                            TextField("Find in page", text: $store.findText).textFieldStyle(.plain).onSubmit { store.action("find:" + store.findText) }
                            tool("Next match", "chevron.down") { store.action("find:" + store.findText) }
                            tool("Close find", "xmark") { store.showFind = false; store.action("stop-find") }
                        }.padding(12).frame(width: 300).background(AavaBrand.salt, in: RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius)).foregroundStyle(AavaBrand.deep).padding(.top, 56)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(AavaGeometry.frameInset)
            .background {
                AavaChromeMaterial(space: store.space, hideMedia: store.locked)
                    .overlay(alignment: .leading) { SpaceTide(spaceID: store.space.id, theme: store.space.theme, direction: store.spaceDirection, reducedMotion: reduceMotion)
                        .frame(width: sidebarVisible ? width + AavaGeometry.frameInset * 2 : AavaGeometry.frameInset).allowsHitTesting(false) }
            }
            .clipShape(RoundedRectangle(cornerRadius: AavaGeometry.frameRadius, style: .continuous))
            .foregroundStyle(ink).environment(\.colorScheme, store.space.theme.darkText ? .light : .dark)
            .onAppear { store.activate() }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: urlHovered)
            .buttonStyle(AavaHoverButton())
            .overlay {
                AavaSidebarResizeHandle(width: width, columns: SidebarSizing.columns(width: width), expanded: sidebarVisible, enabled: !store.hasPanel && !store.showSearch, ink: ink, reduceMotion: reduceMotion, resize: { liveSidebarWidth = SidebarSizing.width($0, container: geometry.size.width) }, commit: { savedSidebarWidth = SidebarSizing.width($0, container: geometry.size.width); liveSidebarWidth = nil }, reveal: { sidebarVisible = true }, collapse: { liveSidebarWidth = nil; sidebarVisible = false })
            }
        }
    }
    private func sidebar(width: Double, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    Spacer().frame(width: 76); Spacer(minLength: 0)
                    tool("Hide sidebar", "sidebar.left") { sidebarVisible = false }
                    if width >= 200 {
                        tool("Back", "chevron.left") { store.action("back") }.disabled(!store.canBack)
                        tool("Forward", "chevron.right") { store.action("forward") }.disabled(!store.canForward)
                    }
                }.frame(height: AavaGeometry.sidebarToolbarHeight)
                if width < 200 {
                    HStack(spacing: 3) {
                        tool("Back", "chevron.left") { store.action("back") }.disabled(!store.canBack)
                        tool("Forward", "chevron.right") { store.action("forward") }.disabled(!store.canForward)
                        Spacer(minLength: 0)
                    }
                }
            }.padding(.top, AavaGeometry.sidebarToolbarTop)
            Button { store.search() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                    Text("Search anything").font(.system(size: 12)).lineLimit(1); Spacer(minLength: 0)
                    if width >= 200 { Text("⌘ L").font(.system(size: 10)).opacity(0.5) }
                }.padding(.horizontal, 10).frame(height: 30).background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
            }.disabled(store.locked)
            Group {
            if store.locked {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(0..<7) { n in RoundedRectangle(cornerRadius: AavaGeometry.controlRadius).fill(ink.opacity(0.25)).frame(width: CGFloat(110 + (n % 3)*27), height: 20) }; Spacer()
                }.padding(12).blur(radius: 7).accessibilityHidden(true).allowsHitTesting(false)
            } else {
                PinnedTabs(store: store, ink: ink, columns: SidebarSizing.columns(width: width), heightBudget: max(96, height * 0.5))
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(store.space.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            tool("New folder", "folder.badge.plus") { store.addFolder() }
                            tool("Space settings", "ellipsis") { store.openSettings() }
                        }.padding(.horizontal, 8).padding(.top, 7).padding(.bottom, 5)
                        sectionLabel("Saved")
                        SavedFolderTree(store: store, parent: nil, depth: 0, ink: ink)
                        if store.space.saved.isEmpty { Text("Save a page with ⌘ D").font(.system(size: 11)).opacity(0.55).padding(.horizontal, 10).padding(.vertical, 8) }
                        Rectangle().fill(ink.opacity(0.10)).frame(height: 1).padding(.vertical, 12).padding(.horizontal, 8)
                        GitHubFolderTree(store: store, live: store.github, ink: ink)
                        HStack(spacing: 2) {
                            sectionLabel("Tabs")
                            Spacer(minLength: 0)
                            Button("Tidy up") { store.tidyTabs() }.font(.system(size: 10)).fixedSize().buttonStyle(AavaHoverButton(inset: 6)).help("Group tabs by website")
                            Button("Clean") { store.openPanel(.cleanup) }.font(.system(size: 10)).fixedSize().buttonStyle(AavaHoverButton(inset: 6))
                        }
                        ForEach(store.space.tabs.filter { !$0.pinned }) { SidebarTabRow(store: store, tab: $0, ink: ink) }
                        Button { store.newTab() } label: {
                            HStack(spacing: 10) { Image(systemName: "plus").frame(width: 17); Text("New tab").lineLimit(1); Spacer(minLength: 0); if width >= 200 { Text("⌘ T").font(.system(size: 10)).opacity(0.5) } }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 34)
                        }.opacity(0.75)
                    }
                }.scrollIndicators(.hidden)
            }
            }.modifier(SpaceContentArrival(id: store.space.id, direction: store.spaceDirection))
            AavaSidebarFooter(store: store, width: width, ink: ink)
        }.padding(.horizontal, AavaGeometry.sidebarInset).padding(.bottom, 12)
            .background { SpaceSwipeRegion(enabled: !store.hasPanel && !store.showSearch && !store.showOnboarding) { store.stepSpace($0) } }
    }
    private func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false).opacity(0.5).padding(.horizontal, 10).padding(.top, 9).padding(.bottom, 4) }
    private var urlBar: some View {
        HStack(spacing: 10) {
            if !sidebarVisible { tool("Show sidebar", "sidebar.left") { sidebarVisible = true } }
            Image(systemName: store.currentURL?.scheme == "https" ? "lock" : "globe").font(.system(size: 10)).opacity(0.6)
            Button { store.search() } label: { Text(store.currentURL?.host ?? "New tab").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
            tool(store.copied ? "Copied" : "Copy URL", store.copied ? "checkmark" : "link") { store.copyURL() }.disabled(store.currentURL == nil)
            tool(store.loading ? "Stop" : "Reload", store.loading ? "xmark" : "arrow.clockwise") { store.action(store.loading ? "stop" : "reload") }
        }.padding(.horizontal, 10).frame(height: 36).background(AavaBrand.salt, in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius)).foregroundStyle(AavaBrand.deep)
    }
    private func tool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 12)).frame(width: 26, height: 28) }.help(title).accessibilityLabel(title)
    }
}

private struct SidebarTabRow: View {
    @ObservedObject var store: MacStore
    let tab: BrowserTab
    let ink: Color
    @State private var hovered = false
    @FocusState private var focused: Bool
    private var selected: Bool { store.tab?.id == tab.id }
    var body: some View {
        HStack(spacing: 0) {
            Button { store.dismissPanels(); store.select(tab.id) } label: {
                HStack(spacing: 9) {
                    SiteIcon(store: store, url: tab.url)
                    Text(tab.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if tab.pinned { Image(systemName: "pin.fill").font(.system(size: 8)).opacity(0.55) }
                    if store.callPolicy.capturing.contains(tab.id) { Image(systemName: "video.fill").font(.system(size: 10)).accessibilityLabel("Camera or microphone active") }
                }.padding(.leading, 10).padding(.trailing, 3).frame(height: 34).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focused)
            Button { store.openPanel(.tab(tab.id)) } label: { Image(systemName: "ellipsis").font(.system(size: 10)).frame(width: 24, height: 26) }
                .help("Tab actions").accessibilityLabel("Actions for " + tab.title).opacity(hovered || selected || focused ? 0.8 : 0).focused($focused)
            Button { store.close(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).frame(width: 24, height: 26) }
                .help("Close tab").accessibilityLabel("Close " + tab.title).opacity(hovered || selected || focused ? 0.75 : 0).focused($focused)
        }.padding(.trailing, 3).background(ink.opacity(selected ? 0.12 : hovered ? 0.065 : 0), in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
            .onHover { hovered = $0 }.overlay { SecondaryClick { store.openPanel(.tab(tab.id)) } }
            .accessibilityElement(children: .contain)
    }
}

struct SavedFolderTree: View {
    @ObservedObject var store: MacStore
    let parent: UUID?
    let depth: Int
    let ink: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.space.saved.filter { $0.parentID == parent }) { item in
                SavedRow(store: store, item: item, ink: ink)
                if item.isFolder && !(store.space.collapsedFolderIDs ?? []).contains(item.id) && depth < 32 {
                    SavedFolderTree(store: store, parent: item.id, depth: depth + 1, ink: ink).padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.10)).frame(width: 1).padding(.leading, 10).allowsHitTesting(false) }
                }
            }
        }
    }
}

private struct SavedRow: View {
    @ObservedObject var store: MacStore
    let item: SavedItem
    let ink: Color
    @State private var hovered = false
    @FocusState private var focused: Bool
    private var collapsed: Bool { (store.space.collapsedFolderIDs ?? []).contains(item.id) }
    var body: some View {
        HStack(spacing: 0) {
            Button {
                if item.isFolder { store.toggleFolder(item.id) }
                else if let url = item.url { store.dismissPanels(); store.newTab(url) }
            } label: {
                HStack(spacing: 7) {
                    if item.isFolder {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .semibold)).frame(width: 9).opacity(0.55)
                        ProviderIcon(style: store.space.iconStyle, name: "folder", fallback: collapsed ? "folder" : "folder.fill", emoji: collapsed ? "📁" : "📂")
                    } else { SiteIcon(store: store, url: item.url).padding(.leading, 2) }
                    Text(item.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }.padding(.leading, 8).frame(height: 33).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focused).accessibilityLabel(item.isFolder ? "\(collapsed ? "Expand" : "Collapse") \(item.title)" : item.title)
            if item.isFolder {
                Button { store.addFolder(parent: item.id) } label: { Image(systemName: "plus").font(.system(size: 10)).frame(width: 22, height: 26) }.accessibilityLabel("New subfolder in " + item.title).opacity(hovered || focused ? 0.75 : 0).focused($focused)
            }
            Button { store.openPanel(.saved(item.id)) } label: { Image(systemName: "ellipsis").font(.system(size: 10)).frame(width: 22, height: 26) }.accessibilityLabel("Edit " + item.title).opacity(hovered || focused ? 0.75 : 0).focused($focused)
            if !item.isFolder {
                Button { store.openPanel(.delete(item.id)) } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 22, height: 26) }.accessibilityLabel("Remove " + item.title).opacity(hovered || focused ? 0.75 : 0).focused($focused)
            }
        }.padding(.trailing, 3).background(ink.opacity(hovered ? 0.065 : 0), in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
            .onHover { hovered = $0 }.overlay { SecondaryClick { store.openPanel(.saved(item.id)) } }
    }
}

struct ChromiumSurface: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> PageMount { PageMount() }
    func updateNSView(_ mount: PageMount, context: Context) { mount.show(view) }
    final class PageMount: NSView {
        private weak var current: NSView?
        func show(_ page: NSView) {
            guard current !== page else { return }
            current?.removeFromSuperview()
            page.frame = bounds; page.autoresizingMask = [.width, .height]
            addSubview(page); current = page
        }
    }
}

private final class FocusAddressField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self); self.selectText(nil)
        }
    }
}

struct AddressField: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var submit: () -> Void
    var move: (Int) -> Void = { _ in }
    var cancel: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = FocusAddressField()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 14); field.placeholderString = "Search or enter address"
        field.setAccessibilityLabel("Search or enter address")
        field.delegate = context.coordinator; field.target = context.coordinator
        field.action = #selector(Coordinator.commit)
        return field
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.parent = self
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.textColor = NSColor(AavaSurfaceColors.ink)
        view.placeholderAttributedString = NSAttributedString(string: "Search or enter address", attributes: [.foregroundColor: NSColor(AavaSurfaceColors.secondary)])
        (view.currentEditor() as? NSTextView)?.insertionPointColor = NSColor(AavaSurfaceColors.accent)
        if view.stringValue != text { view.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        init(_ parent: AddressField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.move(1); return true
            case #selector(NSResponder.moveUp(_:)): parent.move(-1); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel(); return true
            default: return false
            }
        }
        @objc func commit() { parent.submit() }
    }
}

struct ProviderIcon: View {
    let style: IconStyle
    let name: String
    let fallback: String
    let emoji: String
    var body: some View {
        Group {
            if style == .emoji { Text(emoji).font(.system(size: 13)) }
            else if let image = ProviderIconCache.image(style: style, name: name) { Image(nsImage: image).renderingMode(.template).resizable().scaledToFit() }
            else { Image(systemName: fallback).font(.system(size: 13)) }
        }.frame(width: 15, height: 15).accessibilityHidden(true)
    }
}
extension Color {
    init(hex: String) { let v = UInt64(hex, radix: 16) ?? 0xACC5CC; self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, opacity: 1) }
    var hex: String { guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "ACC5CC" }; return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255)) }
}
