import AppKit
import SwiftUI

extension MacStore {
    var spaceDownloads: [BrowserDownload] { locked ? [] : space.downloads ?? [] }
    var activeDownloadCount: Int { spaceDownloads.filter { $0.status.active }.count }
    func downloadAction(_ item: BrowserDownload, _ action: String) {
        guard !locked, item.profile == space.profileID, spaceDownloads.contains(where: { $0.id == item.id }) else { return }
        item.id.withCString { token in item.profile.uuidString.withCString { profile in action.withCString { AavaEngineDownloadAction(token, profile, $0) } } }
    }
    func revealDownload(_ item: BrowserDownload, open: Bool = false) {
        guard !locked, item.profile == space.profileID, item.status == .complete,
              spaceDownloads.contains(where: { $0.id == item.id }) else { return }
        guard !item.path.isEmpty, FileManager.default.fileExists(atPath: item.path) else {
            message = "This file has moved or is no longer on your Mac."; return
        }
        let url = URL(fileURLWithPath: item.path)
        if open { NSWorkspace.shared.open(url) }
        else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func clearFinishedDownloads() {
        guard !locked else { return }
        state.spaces[state.currentSpaceIndex].downloads = spaceDownloads.filter { $0.status.active }; persist()
    }
}

private func downloadDetail(_ item: BrowserDownload) -> String {
    let received = ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file)
    switch item.status {
    case .waiting: return "Waiting to save"
    case .paused: return "Paused · " + received
    case .complete: return received + " · Saved"
    case .cancelled: return "Cancelled"
    case .interrupted: return "Interrupted · Download again from the page"
    case .downloading:
        return item.total > 0 ? received + " of " + ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file) : received + " downloaded"
    }
}

struct AavaDownloadTray: View {
    @ObservedObject var store: MacStore
    let ink: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Downloads").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Button { store.downloadTrayExpanded = false } label: { Image(systemName: "chevron.down").font(.system(size: 10)).frame(width: 24, height: 24) }
                    .accessibilityLabel("Collapse downloads")
            }.padding(.horizontal, 8)
            if store.spaceDownloads.isEmpty {
                Text("Your downloads land here.").font(.system(size: 11)).opacity(0.6).padding(8)
            }
            ForEach(Array(store.spaceDownloads.prefix(2))) { item in
                Button { store.downloads() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.status == .complete ? "doc" : "arrow.down.document").font(.system(size: 15)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text(downloadDetail(item)).font(.system(size: 9)).opacity(0.65).lineLimit(1)
                            if item.status == .downloading || item.status == .paused {
                                if let progress = item.progress { ProgressView(value: progress).progressViewStyle(.linear).tint(ink.opacity(0.65)) }
                                else { ProgressView().progressViewStyle(.linear).tint(ink.opacity(0.65)) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(8)
                }.buttonStyle(AavaHoverButton()).accessibilityLabel(item.name + ", " + downloadDetail(item) + ", Show downloads")
            }
            Button("All downloads") { store.downloads() }.font(.system(size: 10, weight: .medium)).buttonStyle(AavaHoverButton(inset: 8))
        }.padding(4).background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AavaSidebarFooter: View {
    @ObservedObject var store: MacStore
    let width: Double
    let ink: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var visibleSpaces: ArraySlice<BrowserSpace> {
        let capacity = max(1, Int((width - AavaGeometry.sidebarInset * 2 - 40) / 32))
        let start = max(0, min(store.state.currentSpaceIndex - capacity / 2, store.state.spaces.count - capacity))
        return store.state.spaces[start..<min(store.state.spaces.count, start + capacity)]
    }
    var body: some View {
        VStack(spacing: 7) {
            if store.downloadTrayExpanded && !store.locked {
                AavaDownloadTray(store: store, ink: ink).transition(.opacity)
            }
            Rectangle().fill(ink.opacity(0.09)).frame(height: 1).padding(.horizontal, 4)
            HStack(spacing: 4) {
                step("Previous space", "chevron.left", -1)
                Spacer(minLength: 0)
                ForEach(visibleSpaces) { space in
                    Button { store.switchSpace(space.id) } label: {
                        Text(store.isLocked(space.id) ? "🔒" : space.emoji).font(.system(size: 17)).frame(width: 28, height: 32)
                    }.buttonStyle(AavaHoverButton(active: store.space.id == space.id))
                        .accessibilityLabel(store.isLocked(space.id) ? "Private space" : space.name)
                        .help((store.isLocked(space.id) ? "Private space" : space.name) + " · Scroll sideways to switch · ⌘⌥← / ⌘⌥→")
                }
                Spacer(minLength: 0)
                step("Next space", "chevron.right", 1)
            }.frame(height: 36).contentShape(Rectangle())
            HStack(spacing: 0) {
                Button { store.downloadTrayExpanded.toggle() } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.to.line").frame(width: 32, height: 30)
                        if store.activeDownloadCount > 0 {
                            Circle().fill(ink).frame(width: 5, height: 5).padding(4)
                        }
                    }
                }.buttonStyle(AavaHoverButton(active: store.downloadTrayExpanded && !store.locked)).disabled(store.locked)
                    .help("Downloads").accessibilityLabel("Downloads, \(store.activeDownloadCount) active")
                Spacer(minLength: 4)
                utility("History and archive", "clock.arrow.circlepath") { store.openLibrary() }.disabled(store.locked)
                Spacer(minLength: 4)
                utility("Aava settings", "slider.horizontal.3") { store.openSettings(store.locked ? "Browsing" : "Appearance") }
            }.font(.system(size: 12)).padding(.horizontal, 4)
        }.animation(reduced ? nil : .easeOut(duration: 0.16), value: store.downloadTrayExpanded)
    }
    private func step(_ title: String, _ icon: String, _ direction: Int) -> some View {
        Button { store.stepSpace(direction) } label: { Image(systemName: icon).font(.system(size: 9, weight: .medium)).frame(width: 16, height: 30).opacity(0.55) }
            .disabled(store.state.spaces.count < 2).accessibilityLabel(title).help(title)
    }
    private func utility(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 32, height: 30) }.accessibilityLabel(title).help(title)
    }
}

struct AavaDownloads: View {
    @ObservedObject var store: MacStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            panelTitle("Downloads", "Files from \(store.space.name). Your other spaces keep their own lists.")
            if store.spaceDownloads.isEmpty {
                Text("Nothing downloaded here yet.").font(.system(size: 14)).foregroundStyle(AavaSurfaceColors.secondary).padding(.vertical, 20)
            }
            ForEach(store.spaceDownloads) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc").font(.system(size: 22)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            Text(downloadDetail(item)).font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    if item.status == .downloading, let progress = item.progress { ProgressView(value: progress).tint(AavaSurfaceColors.accent) }
                    HStack(spacing: 8) {
                        if item.status == .complete {
                            Button("Open file") { store.revealDownload(item, open: true) }
                            Button("Show in Finder") { store.revealDownload(item) }
                        } else if item.status == .downloading || item.status == .paused {
                            Button(item.status == .paused ? "Resume" : "Pause") { store.downloadAction(item, item.status == .paused ? "resume" : "pause") }
                            Button("Cancel") { store.downloadAction(item, "cancel") }
                        }
                    }.font(.system(size: 11, weight: .medium)).buttonStyle(AavaHoverButton(inset: 8))
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AavaSurfaceColors.field.opacity(0.6), in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
            }
            if store.spaceDownloads.contains(where: { !$0.status.active }) {
                Button("Clear finished from list") { store.clearFinishedDownloads() }.buttonStyle(AavaHoverButton(inset: 10))
                Text("Files stay on your Mac. Files in Downloads are also accessible outside Aava, including when a private space is locked.")
                    .font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
            }
        }
    }
}
