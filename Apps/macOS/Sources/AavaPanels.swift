import SwiftUI

struct AavaPrompt: Decodable, Identifiable {
    var id: String { token }
    let token: String
    let profile: String
    let title: String
    let detail: String
    let accept: String
    let input: Bool
    let preset: String
}
struct FaviconPayload: Decodable { let page: String; let png: String }
enum AavaPanel: Equatable {
    case folder(UUID?), saved(UUID), tab(UUID), sleep(UUID), delete(UUID), importSource, library, cleanup, github, backgroundFile, downloads, arcData
}

struct AavaPanelRouter: View {
    @ObservedObject var store: MacStore
    var closeAction: (() -> Void)? = nil
    @State private var departingContent: AnyView?
    private var routeIdentity: String { "\(store.showSettings)-\(store.showAbout)-\(store.showPrivateSetup)-\(String(describing: store.panel))-\(store.prompts.first?.token ?? "")-\(store.message ?? "")-\(store.importPreview != nil)" }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                AavaMark(color: AavaSurfaceColors.accent).frame(width: 25, height: 25)
                Text("aava").font(.system(size: 17, weight: .medium, design: .rounded)).tracking(-0.6)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 32, height: 32) }
                    .help("Close panel").accessibilityLabel("Close panel")
            }.padding(.leading, AavaGeometry.contentInset).padding(.trailing, AavaGeometry.frameInset).frame(height: AavaGeometry.drawerHeaderHeight)
            Rectangle().fill(AavaSurfaceColors.ink.opacity(0.08)).frame(height: 1)
            ScrollView {
                Group { if store.hasPanel { content } else { departingContent } }.frame(maxWidth: .infinity, alignment: .leading).padding(AavaGeometry.contentInset).frame(maxWidth: .infinity, alignment: .top)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(AavaSurfaceColors.ink).environment(\.colorScheme, store.space.theme.darkText ? .light : .dark)
            .environment(\.aavaSurfaceControls, true).tint(AavaSurfaceColors.accent)
            .buttonStyle(AavaHoverButton()).onExitCommand(perform: close)
            .onChange(of: routeIdentity, initial: true) { _, _ in
                if store.hasPanel { departingContent = AnyView(content) }
            }
            .onChange(of: store.space.id) { _, _ in departingContent = nil }
            .onChange(of: store.locked) { _, locked in if locked { departingContent = nil } }
    }
    private func close() {
        if let closeAction { closeAction(); return }
        if let prompt = store.prompts.first { store.resolvePrompt(prompt, allow: false) }
        else { store.dismissPanels() }
    }
    @ViewBuilder private var content: some View {
        if let prompt = store.prompts.first { AavaPromptView(store: store, prompt: prompt).id(prompt.token) }
        else if let message = store.message {
            VStack(alignment: .leading, spacing: 20) {
                Text("Aava").font(.system(size: 27, weight: .semibold))
                Text(message).font(.system(size: 14)).textSelection(.enabled)
                Button("Got it") { store.message = nil }.buttonStyle(AavaPrimaryButton())
            }
        } else if store.showPrivateSetup { PrivateSpaceSetup(store: store) }
        else if let preview = store.importPreview { ArcImportPreview(store: store, preview: preview) }
        else if store.showAbout { AavaAboutView(close: { store.showAbout = false }) }
        else if let panel = store.panel {
            switch panel {
            case .folder(let parent): FolderEditor(store: store, parent: parent)
            case .saved(let id): SavedEditor(store: store, id: id).id(id)
            case .tab(let id): TabActions(store: store, id: id)
            case .sleep(let id):
                VStack(alignment: .leading, spacing: 18) {
                    panelTitle("Put this tab to sleep?", "The page will reload when reopened. Save any work first.")
                    if store.callPolicy.capturing.contains(id) { Text("This tab is using your camera or microphone. Finish the call before putting it to sleep.") }
                    HStack {
                        Button("Cancel") { store.dismissPanels() }.buttonStyle(AavaHoverButton(inset: 10))
                        Button("Sleep tab") { store.confirmSleep(id) }.buttonStyle(AavaPrimaryButton()).disabled(store.callPolicy.capturing.contains(id))
                    }
                }
            case .delete(let id):
                VStack(alignment: .leading, spacing: 18) {
                    panelTitle("Remove from saved?", "This removes the saved item and any pages or folders inside it. Open tabs stay open.")
                    HStack {
                        Button("Keep it") { store.dismissPanels() }.buttonStyle(AavaHoverButton(inset: 10))
                        Button("Remove") { store.deleteSaved(id); store.dismissPanels() }.buttonStyle(AavaPrimaryButton())
                    }
                }
            case .arcData: ArcMigrationView(store: store, migration: store.arcMigration)
            case .importSource: ArcImportSource(store: store)
            case .library: if !store.locked { AavaLibrary(store: store) }
            case .cleanup: if !store.locked { AavaCleanup(store: store) }
            case .backgroundFile: if !store.locked { BackgroundFilePicker(store: store) }
            case .github: if !store.locked { GitHubFolderSettings(store: store, live: store.github) }
            case .downloads: if !store.locked { AavaDownloads(store: store) }
            }
        } else if store.showSettings { AavaSettings(store: store) }
    }
}

func panelTitle(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.7)
        Text(detail).font(.system(size: 13)).foregroundStyle(AavaSurfaceColors.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct AavaPromptView: View {
    @ObservedObject var store: MacStore
    let prompt: AavaPrompt
    @State private var answer = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            panelTitle(prompt.title, prompt.detail)
            if prompt.input { TextField("Response", text: $answer).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius)) }
            HStack {
                Button("Cancel") { store.resolvePrompt(prompt, allow: false) }.buttonStyle(AavaHoverButton(inset: 12))
                Button(prompt.accept) { store.resolvePrompt(prompt, allow: true, value: answer) }.buttonStyle(AavaPrimaryButton())
            }
        }.onAppear { answer = prompt.preset }
    }
}

struct AavaSettings: View {
    @ObservedObject var store: MacStore
    @State private var spaceName = ""
    @State private var newName = ""
    @State private var emoji = "✨"
    @State private var privateSpace = false
    private let sections = ["Appearance", "Spaces", "Privacy", "Browsing", "Notifications"]
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            panelTitle("Make Aava yours", "Your browser, with a place for everything.")
            HStack(spacing: 3) {
                ForEach(sections, id: \.self) { section in
                    Button { store.settingsSection = section } label: { Text(section).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 10) }
                        .buttonStyle(AavaHoverButton(active: store.settingsSection == section))
                }
            }
            if store.locked && !(["Browsing", "Notifications"].contains(store.settingsSection)) {
                Text("Unlock this space to change its settings.")
            } else {
                switch store.settingsSection {
                case "Spaces": spaces
                case "Privacy": privacy
                case "Browsing": browsing
                case "Notifications": AavaNotificationSettings(center: store.notifications, scope: store.space.id)
                default: appearance
                }
            }
            Divider()
            HStack {
                Button("Import from Arc") { store.previewArcImport() }.buttonStyle(AavaHoverButton(inset: 10))
                Spacer()
                Button("About Aava") { store.dismissPanels(); store.showAbout = true }.buttonStyle(AavaHoverButton(inset: 10))
            }.font(.system(size: 12))
        }.onAppear { spaceName = store.space.name }
    }
    private var appearance: some View { SpaceAppearanceEditor(store: store) }
    private var spaces: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { TextField("Space name", text: $spaceName).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius)); Button("Rename") { store.renameSpace(spaceName) }.buttonStyle(AavaHoverButton(inset: 12)) }
            Divider()
            Text("Create a space").font(.system(size: 18, weight: .semibold))
            HStack {
                TextField("Emoji", text: $emoji).frame(width: 50)
                TextField("Name", text: $newName)
            }.textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
            Toggle("Private space", isOn: $privateSpace).toggleStyle(.switch)
            Text("Each space gets its own cookies, sign-ins and extension storage.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            Button("Create space") {
                if privateSpace { store.beginPrivateSpace(name: newName, emoji: emoji) }
                else { store.addSpace(name: newName, emoji: emoji) }
            }.buttonStyle(AavaPrimaryButton()).disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private var privacy: some View { SpacePrivacyControls(store: store) }
    private var browsing: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Automatic meeting popouts", isOn: Binding(get: { store.callPolicy.enabled }, set: store.autoPopouts)).toggleStyle(.switch)
            Text("Keep an active meeting visible when switching tabs. You can also keep a tab visible from its row actions.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            if !store.locked {
                autoArchiveControls(store: store)
                AavaLinkChoiceSettings(store: store)
                action("History and archive", "clock.arrow.circlepath") { store.openLibrary() }
                action("Tidy up and clean tabs", "sparkles") { store.openPanel(.cleanup) }
                action("GitHub live folder", "arrow.triangle.branch") { store.openPanel(.github) }
            }
            action("Extensions", "puzzlepiece.extension") { store.extensions() }
            action("Mini AI workspace", "rectangle.inset.filled") { MiniControl.shared.show() }
            action("Downloads", "arrow.down.circle") { store.downloads() }
            action("Show extension toolbar", "rectangle.topthird.inset.filled") { store.dismissPanels(); store.action("toolbar") }
            action("Picture in Picture", "pip") { store.dismissPanels(); store.action("pip") }
            Divider()
            Button("Make Aava your default browser") { store.setDefault() }.buttonStyle(AavaPrimaryButton())
        }
    }
    private func action(_ label: String, _ icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { HStack(spacing: 12) { Image(systemName: icon).frame(width: 20); Text(label); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)) }.font(.system(size: 13)).padding(12) }
    }
}

private struct FolderEditor: View {
    @ObservedObject var store: MacStore
    let parent: UUID?
    @State private var title = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            panelTitle(parent == nil ? "New folder" : "New subfolder", "Keep related pages together in your sidebar.")
            TextField("Folder name", text: $title).textFieldStyle(.plain).padding(14).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius)).focused($focused).onSubmit(create)
            Button("Create folder", action: create).buttonStyle(AavaPrimaryButton()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.onAppear { focused = true }
    }
    private func create() { store.createFolder(title: title, parent: parent) }
}

private struct SavedEditor: View {
    @ObservedObject var store: MacStore
    let id: UUID
    @State private var title = ""
    @State private var parent: UUID?
    private var item: SavedItem? { store.space.saved.first { $0.id == id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let item {
                panelTitle(item.isFolder ? "Folder details" : "Saved page", item.url?.host ?? "Organize your saved pages and subfolders.")
                TextField("Name", text: $title).textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
                Text("Keep in").font(.system(size: 13, weight: .semibold))
                destination("Saved · top level", nil)
                ForEach(store.space.saved.filter { $0.isFolder && store.state.canMoveSaved(id, to: $0.id) }) { folder in destination(folder.title, folder.id) }
                Button("Save changes") { store.renameSaved(id, title: title); store.moveSaved(id, parent: parent); store.dismissPanels() }.buttonStyle(AavaPrimaryButton()).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Divider()
                if item.isFolder {
                    Button("New subfolder") { store.addFolder(parent: id) }.buttonStyle(AavaHoverButton(inset: 10))
                    Button("Save current page here") { store.savePage(parent: id); store.dismissPanels() }.buttonStyle(AavaHoverButton(inset: 10)).disabled(store.currentURL == nil)
                }
                Button("Remove from saved") { store.openPanel(.delete(id)) }.foregroundStyle(.red).buttonStyle(AavaHoverButton(inset: 10))
            }
        }.onAppear { title = item?.title ?? ""; parent = item?.parentID }
    }
    private func destination(_ label: String, _ value: UUID?) -> some View {
        Button { parent = value } label: { HStack { Image(systemName: "folder"); Text(label); Spacer(); if parent == value { Image(systemName: "checkmark") } }.font(.system(size: 12)).padding(10) }.buttonStyle(AavaHoverButton(active: parent == value))
    }
}

private struct TabActions: View {
    @ObservedObject var store: MacStore
    let id: UUID
    private var tab: BrowserTab? { store.space.tabs.first { $0.id == id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let tab {
                panelTitle(tab.displayTitle, tab.url?.host ?? "New tab")
                Button(tab.pinned ? "Unpin tab" : "Pin to top") { store.pin(id); store.dismissPanels() }.buttonStyle(AavaHoverButton(inset: 12))
                if tab.pinned { PinnedTileEditor(store: store, id: id).id(id) }
                if tab.pinnedURL != nil && tab.pinned { Button("Reset pinned tab") { store.resetPinned(id); store.dismissPanels() }.buttonStyle(AavaHoverButton(inset: 12)) }
                Button(store.callPolicy.manual.contains(id) ? "Stop keeping visible" : "Keep visible when switching tabs") { store.pinCall(id); store.dismissPanels() }.buttonStyle(AavaHoverButton(inset: 12)).disabled(tab.url == nil)
                Button("Put tab to sleep") { store.sleep(id) }.buttonStyle(AavaHoverButton(inset: 12)).disabled(store.isSleeping(id) || tab.url == nil || store.callPolicy.capturing.contains(id))
                Divider()
                Text("Save to sidebar").font(.system(size: 13, weight: .semibold))
                saveDestination("Saved · top level", nil)
                ForEach(store.space.saved.filter(\.isFolder)) { folder in saveDestination(folder.title, folder.id) }
                Divider()
                Button("Close tab") { store.dismissPanels(); store.close(id) }.buttonStyle(AavaHoverButton(inset: 12))
            }
        }
    }
    private func saveDestination(_ title: String, _ parent: UUID?) -> some View {
        Button { store.select(id); store.savePage(parent: parent); store.dismissPanels() } label: { HStack { Image(systemName: "folder"); Text(title); Spacer(); Image(systemName: "plus") }.font(.system(size: 12)).padding(10) }.disabled(tab?.url == nil)
    }
}

private struct ArcImportSource: View {
    @ObservedObject var store: MacStore
    @State private var path = "~/Library/Application Support/Arc/StorableSidebar.json"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            panelTitle("Bring Arc along", "Start with your spaces, then bring over more from each Arc profile. Arc stays unchanged.")
            Text("Sidebar file").font(.system(size: 12, weight: .semibold))
            TextField("Path to StorableSidebar.json", text: $path).textFieldStyle(.plain).padding(14).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius)).onSubmit { store.loadArcImport(path: path) }
            Text("The usual Mac location is filled in. You can paste another file path above.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            Button("Preview spaces") { store.loadArcImport(path: path) }.buttonStyle(AavaPrimaryButton())
            Divider().padding(.vertical, 4)
            panelTitle("Your browsing, too", "Bookmarks, history, an extension restore list and optional website sessions. Passwords have a separate import step.")
            Button("More from Arc") { store.openPanel(.arcData) }.buttonStyle(AavaPrimaryButton())
        }
    }
}
