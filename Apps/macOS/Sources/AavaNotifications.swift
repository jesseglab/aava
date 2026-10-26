import AppKit
import SwiftUI

@MainActor final class AavaNotifications: ObservableObject {
    @Published private(set) var preferences: NotificationPreferences
    @Published private(set) var queue = ToastQueue()
    @Published var hovered = false { didSet { schedule() } }
    @Published private(set) var saveError: String?
    private let repository: NotificationPreferencesRepository
    private var expiry: Task<Void, Never>?
    var paused = false { didSet { schedule() } }
    var stackHeight: CGFloat { 98 + CGFloat(max(0, queue.items.count - 1)) * (expanded ? 94 : 10) }
    var expanded: Bool { preferences.expanded || hovered || NSWorkspace.shared.isVoiceOverEnabled }
    init(root: URL) {
        repository = NotificationPreferencesRepository(fileURL: root.appendingPathComponent("notifications.json"))
        preferences = (try? repository.load()) ?? NotificationPreferences()
    }
    func configure(position: ToastPosition? = nil, expanded: Bool? = nil) {
        var next = preferences
        if let position { next.position = position }
        if let expanded { next.expanded = expanded }
        do { try repository.save(next); preferences = next; saveError = nil }
        catch { saveError = "Notification preferences couldn’t be saved. Please try again." }
    }
    func show(_ title: String, detail: String = "", scope: UUID) {
        queue.push(AavaToast(title: title, detail: detail, scope: scope)); schedule()
        if let window = NSApp.mainWindow {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: title + ". " + detail, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
    func dismiss(_ id: UUID) { queue.remove(id); schedule() }
    func clear() { expiry?.cancel(); queue.clear(); hovered = false }
    private func schedule() {
        expiry?.cancel()
        guard !queue.items.isEmpty, !hovered, !paused, !NSWorkspace.shared.isVoiceOverEnabled else { return }
        let ids = queue.items.map(\.id)
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            for id in ids { self.queue.remove(id) }
        }
    }
}

struct AavaNotificationSettings: View {
    @ObservedObject var center: AavaNotifications
    let scope: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Little updates, your way.").font(.system(size: 20, weight: .semibold))
            Text("Quick confirmations appear without interrupting your page. These preferences apply across Aava.").font(.system(size: 13)).foregroundStyle(AavaSurfaceColors.secondary)
            Text("Position").font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ToastPosition.allCases, id: \.self) { position in
                    Button { center.configure(position: position) } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: alignment(position)) {
                                RoundedRectangle(cornerRadius: AavaGeometry.insetRadius(AavaGeometry.surfaceRadius, by: AavaGeometry.frameInset)).stroke(AavaSurfaceColors.ink.opacity(0.16), lineWidth: 1).frame(height: 43)
                                RoundedRectangle(cornerRadius: AavaGeometry.insetRadius(AavaGeometry.surfaceRadius, by: AavaGeometry.frameInset + 6)).fill(center.preferences.position == position ? AavaSurfaceColors.accent : AavaSurfaceColors.ink.opacity(0.24)).frame(width: 25, height: 9).padding(6)
                            }
                            Text(position.rawValue).font(.system(size: 11))
                        }.padding(AavaGeometry.frameInset)
                    }.buttonStyle(AavaHoverButton(radius: AavaGeometry.surfaceRadius, active: center.preferences.position == position))
                        .accessibilityLabel(position.rawValue).accessibilityAddTraits(center.preferences.position == position ? .isSelected : [])
                }
            }
            Text("Expand").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                ForEach([false, true], id: \.self) { expanded in
                    Button { center.configure(expanded: expanded) } label: { Text(expanded ? "Expand" : "Default").font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 12) }
                        .buttonStyle(AavaHoverButton(active: center.preferences.expanded == expanded))
                        .accessibilityAddTraits(center.preferences.expanded == expanded ? .isSelected : [])
                }
            }
            Text("Default keeps updates in a small stack; hover to read them all. Expand keeps up to three fully visible. Swipe toward the nearest edge to dismiss.")
                .font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Preview notifications") {
                center.show("Page saved", detail: "Ready in your sidebar.", scope: scope)
                center.show("Folder created", detail: "A little room for something new.", scope: scope)
                center.show("Link copied", detail: "Ready to paste.", scope: scope)
            }.buttonStyle(AavaPrimaryButton())
            if let error = center.saveError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }
    }
    private func alignment(_ p: ToastPosition) -> Alignment {
        Alignment(horizontal: p.isCenter ? .center : p.isLeft ? .leading : .trailing, vertical: p.isTop ? .top : .bottom)
    }
}

struct AavaToastStack: View {
    @ObservedObject var center: AavaNotifications
    @ObservedObject var store: MacStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var top: Bool { center.preferences.position.isTop }
    var body: some View {
        ZStack(alignment: top ? .top : .bottom) {
            ForEach(Array(center.queue.items.enumerated()), id: \.element.id) { index, toast in
                AavaToastCard(space: store.space, toast: toast, position: center.preferences.position) { center.dismiss(toast.id) }
                    .scaleEffect(center.expanded ? 1 : 1 - Double(index) * 0.045, anchor: top ? .top : .bottom)
                    .offset(y: Double(index) * (center.expanded ? 94 : 10) * (top ? 1 : -1))
                    .zIndex(Double(3 - index))
                    .allowsHitTesting(center.expanded || index == 0)
                    .accessibilityHidden(!center.expanded && index > 0)
                    .transition(reduceMotion ? .opacity : .offset(y: top ? -18 : 18).combined(with: .opacity))
            }
        }.padding(8).frame(width: 376, height: center.stackHeight, alignment: top ? .top : .bottom)
            .onHover { center.hovered = $0 }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.88), value: center.queue.items)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88), value: center.expanded)
            .environment(\.colorScheme, store.space.theme.darkText ? .light : .dark)
            .environment(\.aavaSurfaceControls, true)
    }
}

private struct AavaToastCard: View {
    let space: BrowserSpace
    let toast: AavaToast
    let position: ToastPosition
    let dismiss: () -> Void
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(AavaSurfaceColors.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(toast.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if !toast.detail.isEmpty { Text(toast.detail).font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 28) }
                .buttonStyle(AavaHoverButton()).accessibilityLabel("Dismiss \(toast.title)")
        }.padding(.horizontal, 16).frame(height: 82).background { AavaChromeMaterial(space: space, isDrawer: true, cornerRadius: AavaGeometry.surfaceRadius) }
            .overlay { RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius).stroke(AavaSurfaceColors.ink.opacity(0.16), lineWidth: 1) }
            .foregroundStyle(AavaSurfaceColors.ink).offset(reduceMotion ? .zero : drag)
            .contentShape(RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius))
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in drag = constrained(value.translation) }.onEnded { value in
                let projected = constrained(value.predictedEndTranslation)
                if abs(projected.width) > 80 || abs(projected.height) > 60 { dismiss() }
                else { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { drag = .zero } }
            })
            .accessibilityElement(children: .contain)
    }
    private func constrained(_ size: CGSize) -> CGSize {
        if position.isCenter { return CGSize(width: 0, height: position.isTop ? min(0, size.height) : max(0, size.height)) }
        return CGSize(width: position.isLeft ? min(0, size.width) : max(0, size.width), height: 0)
    }
}
