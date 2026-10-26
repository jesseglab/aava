import AavaCore
import SwiftUI
import WebKit

struct BrowserView: View {
    @EnvironmentObject var store: BrowserStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var library = false
    @State private var settings = false
    @State private var downloads = false
    @State private var sharing = false
    private var wide: Bool { sizeClass == .regular }
    var body: some View {
        HStack(spacing: 8) {
            if wide { LibraryView(close: {}).frame(width: 248) }
            VStack(spacing: 7) {
                if wide { addressBar }
                Group {
                    if let webView = store.activeWebView { WebSurface(webView: webView) }
                    else { startPage }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !wide { addressBar }
                HStack {
                    control("Back", "chevron.left", action: store.back).disabled(!store.canGoBack)
                    control("Forward", "chevron.right", action: store.forward).disabled(!store.canGoForward)
                    Spacer(minLength: 0)
                    if !wide { control("Tabs and saved pages", "sidebar.left") { library = true } }
                    control("New tab", "plus") { store.newTab(); store.addressRequested = true }
                    Menu {
                        Button("Save page", systemImage: "bookmark") { store.savePage() }.disabled(store.currentURL == nil)
                        Button("Share page", systemImage: "square.and.arrow.up") { sharing = true }.disabled(store.currentURL == nil)
                        Button("Downloads", systemImage: "arrow.down.circle") { downloads = true }
                        Button("Customize this space", systemImage: "paintpalette") { settings = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Browser menu")
                }.foregroundStyle(store.space.theme.darkText ? Color.black.opacity(0.75) : .white)
            }
        }
        .padding(8)
        .background(LinearGradient(colors: [Color(hex: store.space.theme.top), Color(hex: store.space.theme.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .tint(.primary)
        .sheet(isPresented: $store.addressRequested) { AddressView() }
        .sheet(isPresented: $library) {
            NavigationStack { LibraryView(close: { library = false }).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { library = false } } } }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $downloads) { DownloadsView() }
        .sheet(isPresented: $sharing) { if let url = store.currentURL { ShareView(url: url) } }
        .alert("Aava", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    private var addressBar: some View {
        HStack(spacing: 2) {
            Button { store.addressRequested = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: store.currentURL == nil ? "magnifyingglass" : store.currentURL?.scheme == "https" ? "lock" : "globe")
                    Text(store.currentURL?.host ?? "Search or enter address").lineLimit(1)
                    Spacer(minLength: 0)
                }.font(.subheadline).padding(.leading, 13).frame(minHeight: 44)
            }.accessibilityLabel("Search or enter address")
            control("Copy URL", "link", action: store.copyURL).disabled(store.currentURL == nil)
            control(store.loading ? "Stop" : "Reload", store.loading ? "xmark" : "arrow.clockwise", action: store.reloadOrStop).disabled(store.currentURL == nil)
        }
        .foregroundStyle(Color.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(alignment: .bottomLeading) { if store.loading { ProgressView(value: store.progress).padding(.horizontal, 12).tint(.secondary) } }
    }
    private var startPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("aava").font(.system(size: 64, weight: .medium, design: .rounded)).tracking(-4)
            Text("Room to browse.").font(.title3).foregroundStyle(.secondary)
            Button { store.addressRequested = true } label: { Label("Where to?", systemImage: "magnifyingglass").padding(.horizontal, 28).padding(.vertical, 14).background(.quaternary, in: Capsule()) }
            Spacer()
            SpaceStrip().padding(.bottom, 20)
        }.frame(maxWidth: .infinity)
    }
    private func control(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(title)
    }
}

struct WebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ host: UIView, context: Context) {
        guard webView.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview(); host.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([webView.leadingAnchor.constraint(equalTo: host.leadingAnchor), webView.trailingAnchor.constraint(equalTo: host.trailingAnchor), webView.topAnchor.constraint(equalTo: host.topAnchor), webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
    }
}

struct SpaceStrip: View {
    @EnvironmentObject var store: BrowserStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.state.spaces) { space in
                    Button { store.switchSpace(space.id) } label: {
                        Text(space.emoji).font(.title3).frame(width: 44, height: 44)
                            .background(store.space.id == space.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.accessibilityLabel(space.name).accessibilityAddTraits(store.space.id == space.id ? .isSelected : [])
                }
            }.padding(.horizontal, 8)
        }.fixedSize(horizontal: false, vertical: true)
        .simultaneousGesture(DragGesture(minimumDistance: 45).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) { store.stepSpace(value.translation.width < 0 ? 1 : -1) }
        })
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: BrowserStore
    let close: () -> Void
    @State private var folderPrompt = false
    @State private var folderName = ""
    @State private var customize = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.space.name).font(.title2.weight(.semibold))
                Spacer()
                Button { customize = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Customize space")
            }.padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if store.space.tabs.contains(where: \.pinned) {
                        caption("PINNED")
                        ForEach(store.space.tabs.filter(\.pinned)) { tab in tabRow(tab) }
                    }
                    DisclosureGroup {
                        SavedBranch(parent: nil, depth: 0, close: close)
                        Button { folderPrompt = true } label: { Label("New folder", systemImage: "folder.badge.plus").font(.subheadline).frame(minHeight: 44) }
                    } label: { Text("Saved").font(.headline).frame(minHeight: 44) }.padding(.vertical, 10)
                    caption("TABS")
                    ForEach(store.space.tabs.filter { !$0.pinned }) { tab in tabRow(tab) }
                    Button { store.newTab(); close(); store.addressRequested = true } label: { Label("New tab", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44) }.font(.subheadline)
                }.padding(.horizontal, 16)
            }
            SpaceStrip()
        }.padding(.vertical, 10)
        .sheet(isPresented: $customize) { SettingsView() }
        .alert("New folder", isPresented: $folderPrompt) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) { folderName = "" }
            Button("Create") { store.addFolder(folderName); folderName = "" }
        }
    }
    private func caption(_ text: String) -> some View { Text(text).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.top, 8) }
    private func tabRow(_ tab: BrowserTab) -> some View {
        HStack(spacing: 5) {
            Button { store.selectTab(tab.id); close() } label: {
                HStack(spacing: 10) {
                    SpaceIcon(name: tab.pinned ? "pin" : "globe", emoji: tab.pinned ? "📌" : "🌐")
                    Text(tab.title).font(.subheadline).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
            }
            Button { store.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44) }.accessibilityLabel("Close \(tab.title)")
        }
        .padding(.leading, 9)
        .background(store.currentTab?.id == tab.id ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu { Button(tab.pinned ? "Unpin tab" : "Pin tab", systemImage: "pin") { store.togglePin(tab.id) } }
    }
}

struct SavedBranch: View {
    @EnvironmentObject var store: BrowserStore
    let parent: UUID?
    let depth: Int
    let close: () -> Void
    @State private var newParent: UUID?
    @State private var prompt = false
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.space.saved.filter { $0.parentID == parent }) { item in
                if item.isFolder {
                    DisclosureGroup {
                        if depth < 20 { SavedBranch(parent: item.id, depth: depth + 1, close: close).padding(.leading, 8) }
                        Menu("Add to folder") {
                            Button("Save current page") { store.savePage(parent: item.id) }.disabled(store.currentURL == nil)
                            Button("New subfolder") { newParent = item.id; prompt = true }
                        }.font(.caption).frame(minHeight: 44)
                    } label: {
                        HStack { SpaceIcon(name: "folder", emoji: "📁"); Text(item.title).font(.subheadline) }.frame(minHeight: 44)
                    }.contextMenu { Button("Delete folder and contents", role: .destructive) { store.removeSaved(item.id) } }
                } else {
                    Button { if let url = item.url { store.newTab(url: url); close() } } label: {
                        HStack { SpaceIcon(name: "document", emoji: "📄"); Text(item.title).font(.subheadline).lineLimit(1) }.frame(minHeight: 44)
                    }.contextMenu { Button("Delete saved page", role: .destructive) { store.removeSaved(item.id) } }
                }
            }
        }.alert("New subfolder", isPresented: $prompt) {
            TextField("Folder name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") { store.addFolder(name, parent: newParent); name = "" }
        }
    }
}

struct SpaceIcon: View {
    @EnvironmentObject var store: BrowserStore
    let name: String
    let emoji: String
    var body: some View {
        Group {
            if store.space.iconStyle == .emoji { Text(emoji) }
            else { Image("\(store.space.iconStyle.rawValue)-\(name)").renderingMode(.template).resizable().scaledToFit() }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}

struct AddressView: View {
    @EnvironmentObject var store: BrowserStore
    @Environment(\.dismiss) var dismiss
    @State private var input = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Search or enter address", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.webSearch).submitLabel(.go).focused($focused)
                    .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 14)).onSubmit(go)
                if let url = store.currentURL { Text(url.absoluteString).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                Button("Go", action: go).buttonStyle(.borderedProminent).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }.padding(20).navigationTitle("Where to?").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { input = store.currentURL?.absoluteString ?? ""; focused = true }
        }.presentationDetents([.medium, .large])
    }
    private func go() { store.navigate(input); dismiss() }
}

struct SettingsView: View {
    @EnvironmentObject var store: BrowserStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var emoji = "✨"
    var body: some View {
        NavigationStack {
            Form {
                Section("\(store.space.emoji)  \(store.space.name)") {
                    HStack {
                        ForEach(Array([SpaceTheme.tide, .dusk, .apricot, .sage].enumerated()), id: \.offset) { index, theme in
                            Button { store.setTheme(theme) } label: {
                                Circle().fill(LinearGradient(colors: [Color(hex: theme.top), Color(hex: theme.bottom)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 44, height: 44).overlay { if store.space.theme == theme { Image(systemName: "checkmark").foregroundStyle(theme.darkText ? .black : .white) } }
                            }.buttonStyle(.plain).accessibilityLabel(["Tide", "Dusk", "Apricot", "Sage"][index])
                        }
                    }
                    ColorPicker("Background top", selection: Binding(get: { Color(hex: store.space.theme.top) }, set: { var t = store.space.theme; t.top = $0.hex; store.setTheme(t) }), supportsOpacity: false)
                    ColorPicker("Background bottom", selection: Binding(get: { Color(hex: store.space.theme.bottom) }, set: { var t = store.space.theme; t.bottom = $0.hex; store.setTheme(t) }), supportsOpacity: false)
                    Toggle("Dark controls", isOn: Binding(get: { store.space.theme.darkText }, set: { var t = store.space.theme; t.darkText = $0; store.setTheme(t) }))
                    Picker("Icons", selection: Binding(get: { store.space.iconStyle }, set: store.setIconStyle)) { ForEach(IconStyle.allCases, id: \.self) { Text($0.title).tag($0) } }
                }
                Section("New space · separate sign-ins") {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                    Button("Create space") { store.addSpace(name: name, emoji: emoji); name = ""; dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Default browser") {
                    Text("Default-browser selection will be available after Geeklab’s signed build receives Apple’s browser entitlement.").font(.footnote).foregroundStyle(.secondary)
                    Button("Open default app settings") {
                        if #available(iOS 18.3, *), let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Section { Text("Aava · Development build\nLocal sessions. Sync and desktop extensions are not included in this build.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Make it yours").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject var store: BrowserStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                if store.downloads.isEmpty { ContentUnavailableView("No downloads yet", systemImage: "arrow.down.circle", description: Text("Downloaded files are stored on this device.")) }
                ForEach(store.downloads, id: \.self) { url in ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "doc") } }
            }.navigationTitle("Downloads").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0xACC5CC
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
