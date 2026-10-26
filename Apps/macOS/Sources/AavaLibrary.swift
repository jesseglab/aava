import AppKit
import SwiftUI

struct AavaLibrary: View {
    @ObservedObject var store: MacStore
    @State private var query = ""
    @State private var confirmingClear = false
    private var archive: Bool { store.librarySection == "Archive" }
    private var rows: [LibraryRow] {
        let all = archive ? (store.space.archive ?? []).map { LibraryRow(id: $0.id, title: $0.tab.title, url: $0.tab.url, date: $0.closedAt, tag: $0.reason == .automatic ? "auto" : $0.reason == .clean ? "clean" : "") } : (store.space.history ?? []).map { LibraryRow(id: $0.id, title: $0.title, url: $0.url, date: $0.visitedAt, tag: "") }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || ($0.url?.absoluteString.localizedCaseInsensitiveContains(q) ?? false) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        let visibleRows = rows
        let grouped = Dictionary(grouping: visibleRows) { Calendar.current.startOfDay(for: $0.date) }
        let days = grouped.keys.sorted(by: >)
        VStack(alignment: .leading, spacing: 20) {
            panelTitle("Library", "\(store.space.emoji) \(store.space.name) · History and closed tabs for this space.")
            HStack(spacing: 6) {
                ForEach(["History", "Archive"], id: \.self) { section in
                    Button { store.librarySection = section; confirmingClear = false } label: { Text(section).font(.system(size: 12, weight: .medium)).padding(10) }.buttonStyle(AavaHoverButton(active: store.librarySection == section))
                }
                Spacer(); Text("\(visibleRows.count) \(visibleRows.count == 1 ? "page" : "pages")").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            }
            HStack { Image(systemName: "magnifyingglass"); TextField(archive ? "Search archived tabs" : "Search history", text: $query).textFieldStyle(.plain) }.font(.system(size: 13)).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
            if visibleRows.isEmpty { Text(query.isEmpty ? (archive ? "Closed tabs will be waiting here." : "Pages you visit will appear here.") : "No matching pages.").foregroundStyle(AavaSurfaceColors.secondary).padding(.vertical, 30) }
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    Text(dayTitle(day)).font(.system(size: 12, weight: .semibold)).foregroundStyle(AavaSurfaceColors.secondary).padding(.top, 14)
                    Divider()
                    ForEach(grouped[day] ?? []) { row in
                        HStack(spacing: 6) {
                            Button { if archive { store.restoreArchived(row.id) } else if let url = row.url { store.openURL(url) } } label: {
                                HStack(spacing: 12) {
                                    SiteIcon(store: store, url: row.url)
                                    VStack(alignment: .leading, spacing: 4) { Text(row.title).font(.system(size: 13)).lineLimit(1); Text(row.url?.absoluteString ?? "").font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary).lineLimit(1).truncationMode(.middle) }
                                    Spacer(minLength: 4)
                                    if !row.tag.isEmpty { Text(row.tag).font(.system(size: 10)).foregroundStyle(AavaSurfaceColors.secondary) }
                                    Text(row.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
                                }.padding(.vertical, 10).padding(.horizontal, 8).contentShape(Rectangle())
                            }.accessibilityLabel((archive ? "Restore " : "Open ") + row.title)
                            Button { if let url = row.url { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string); store.notifications.show("Link copied", scope: store.space.id) } } label: { Image(systemName: "link").font(.system(size: 12)).frame(width: 28, height: 30) }.accessibilityLabel("Copy link for " + row.title)
                        }
                    }
                }
            }
            Divider()
            if confirmingClear {
                Text(archive ? "Permanently clear this space’s archive? Open and saved tabs stay in place." : "Clear Aava’s history suggestions in this space? Chromium’s own history is separate.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
                HStack {
                    Button("Cancel") { confirmingClear = false }.buttonStyle(AavaHoverButton(inset: 10))
                    Button("Clear \(archive ? "archive" : "history")") { store.clearLibrary(archive); confirmingClear = false }.buttonStyle(AavaPrimaryButton())
                }
            } else { Button("Clear \(archive ? "archive" : "history")…") { confirmingClear = true }.buttonStyle(AavaHoverButton(inset: 10)).disabled(visibleRows.isEmpty) }
            if !archive { Text("Keeps your 10,000 most recently visited addresses in this space. History starts with this update. Closed tabs are kept separately in Archive.").font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary) }
        }.onChange(of: store.space.id) { _, _ in query = ""; confirmingClear = false }
    }
    private func dayTitle(_ date: Date) -> String { Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInYesterday(date) ? "Yesterday" : date.formatted(date: .abbreviated, time: .omitted) }
    private struct LibraryRow: Identifiable { let id: UUID; let title: String; let url: URL?; let date: Date; let tag: String }
}

struct AavaCleanup: View {
    @ObservedObject var store: MacStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            panelTitle("A little breathing room", "Tidy changes the order. Clean archives duplicate and empty tabs. Closed pages remain in Library → Archive.")
            Button("Tidy up · group by website") { store.tidyTabs(); store.dismissPanels() }.buttonStyle(AavaPrimaryButton())
            Button("Clean \(store.cleanupCandidates.count) duplicate or empty tabs") { store.cleanTabs() }.buttonStyle(AavaHoverButton(inset: 12)).disabled(store.cleanupCandidates.isEmpty)
            Button("Archive other unpinned tabs") { store.cleanTabs(all: true) }.buttonStyle(AavaHoverButton(inset: 12))
            Text("Your current tab, pinned tabs, calls, popouts and active downloads stay open. Pages that warn about unsaved changes also stay open. Websites must provide that warning to protect unsaved work.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            Divider()
            autoArchiveControls(store: store)
        }
    }
}
@MainActor @ViewBuilder func autoArchiveControls(store: MacStore) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Auto-archive inactive tabs").font(.system(size: 15, weight: .semibold))
        HStack(spacing: 4) { ForEach(AutoArchiveInterval.allCases, id: \.self) { interval in
            Button { store.autoArchive(interval.rawValue) } label: { Text(interval.title).font(.system(size: 12)).padding(10) }.buttonStyle(AavaHoverButton(active: (store.space.autoArchiveHours ?? 0) == interval.rawValue))
        } }
        Text("Applies to this space. Checks run once a minute while it’s selected and unlocked. Off until you choose a time.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
    }
}
