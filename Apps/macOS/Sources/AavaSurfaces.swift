import AppKit
import Combine
import SwiftUI

private final class AavaSurfaceWindow: NSPanel {
    var acceptsFocus = false
    override var canBecomeKey: Bool { acceptsFocus }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if HoverPasteView.consumePaste(event, in: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor final class AavaSurfaceState: ObservableObject {
    @Published var visible = false
    var close: () -> Void = {}
}

// Child windows put Aava chrome above Chromium's native child surface. The toast
// window covers only its stack; the rest of the live page keeps receiving input.
@MainActor final class AavaSurfaces {
    private weak var parent: NSWindow?
    private let store: MacStore
    private let drawer = AavaSurfaceWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    private let command = AavaSurfaceWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    private var showingCommand = false
    private var commandPrevious: NSWindow?
    private let toast = AavaSurfaceWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let linkChoice = AavaSurfaceWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var showingLink = false
    private var linkPrevious: NSWindow?
    private var linkKeyboardMonitor: Any?
    private let state = AavaSurfaceState()
    private var subscriptions = Set<AnyCancellable>()
    private var pendingClose: DispatchWorkItem?
    private var pendingToastClose: DispatchWorkItem?
    private var wasLocked = false
    private var previouslyFocused: NSWindow?
    private var showing = false
    private var syncQueued = false
    private var lastScope: UUID
    init(parent: NSWindow, store: MacStore) {
        self.parent = parent; self.store = store; lastScope = store.space.id
        for surface in [drawer, toast, command, linkChoice] {
            surface.isOpaque = false; surface.backgroundColor = .clear; surface.hasShadow = false
            surface.isReleasedWhenClosed = false; surface.isMovableByWindowBackground = false
            surface.collectionBehavior = [.fullScreenAuxiliary]; surface.hidesOnDeactivate = false
            surface.title = "Aava"
        }
        drawer.acceptsFocus = true; command.acceptsFocus = true
        linkChoice.acceptsFocus = true
        linkKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let self, event.window === self.linkChoice { self.store.linkChoices.held = true }
            return event
        }
        linkChoice.contentView = NSHostingView(rootView: AavaLinkChoiceCard(choices: store.linkChoices, store: store).ignoresSafeArea())
        drawer.contentView = NSHostingView(rootView: AavaDrawer(store: store, state: state).ignoresSafeArea())
        toast.contentView = NSHostingView(rootView: AavaToastStack(center: store.notifications, store: store).ignoresSafeArea())
        state.close = { [weak self] in self?.close() }
        store.objectWillChange.merge(with: store.notifications.objectWillChange)
            .sink { [weak self] in self?.scheduleSync() }.store(in: &subscriptions)
        store.linkChoices.$request.sink { [weak self] _ in self?.scheduleSync() }.store(in: &subscriptions)
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.publisher(for: name, object: parent).sink { [weak self] _ in self?.sync() }.store(in: &subscriptions)
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                guard let self else { return }; self.store.notifications.paused = !NSApp.isActive
            }.store(in: &subscriptions)
        }
        sync()
    }
    private func attach(_ surface: NSWindow) {
        guard let parent else { return }
        if surface.parent != parent { parent.addChildWindow(surface, ordered: .above) }
        surface.order(.above, relativeTo: parent.childWindows?.filter { $0 !== surface }.last?.windowNumber ?? parent.windowNumber)
    }
    private func scheduleSync() {
        guard !syncQueued else { return }; syncQueued = true
        DispatchQueue.main.async { [weak self] in self?.syncQueued = false; self?.sync() }
    }
    func sync() {
        SpaceSwitchMetrics.surfaceSyncs += 1
        guard let parent, parent.isVisible else {
            store.linkChoices.available = false
            drawer.orderOut(nil); toast.orderOut(nil); command.orderOut(nil); linkChoice.orderOut(nil); return
        }
        store.linkChoices.checkContext()
        let offersLink = store.linkChoices.request != nil && !store.locked && !store.hasPanel && !store.showSearch && !store.showOnboarding
        store.linkChoices.available = offersLink && !parent.isMiniaturized
        let frame = parent.convertToScreen(parent.contentView?.bounds ?? .zero)
        if offersLink {
            let width = min(420.0, frame.width - 32)
            let rect = NSRect(x: frame.maxX - width - 16, y: frame.maxY - 44 - 184, width: width, height: 184)
            if linkChoice.frame != rect { linkChoice.setFrame(rect, display: false) }
            attach(linkChoice)
            if !showingLink {
                showingLink = true; linkPrevious = NSApp.keyWindow; linkChoice.makeKey()
            }
        } else {
            let focused = linkChoice.isKeyWindow
            linkChoice.orderOut(nil); parent.removeChildWindow(linkChoice)
            if focused {
                if let previous = linkPrevious, previous.isVisible { previous.makeKey() } else { parent.makeKey() }
            }
            showingLink = false; linkPrevious = nil
        }
        if store.hasPanel && drawer.frame != frame { drawer.setFrame(frame, display: false) }
        if store.showSearch && command.frame != frame { command.setFrame(frame, display: false) }
        let changedSpace = lastScope != store.space.id; lastScope = store.space.id
        let becameLocked = store.locked && !wasLocked; wasLocked = store.locked
        if changedSpace || becameLocked {
            pendingClose?.cancel(); state.visible = false
            showing = false; drawer.orderOut(nil); parent.removeChildWindow(drawer)
        }
        if store.hasPanel {
            pendingClose?.cancel()
            attach(drawer)
            if !showing {
                showing = true; previouslyFocused = NSApp.keyWindow
                drawer.makeKey()
                DispatchQueue.main.async { [weak self] in self?.state.visible = true }
            }
        } else if showing {
            state.visible = false; showing = false
            if store.locked || changedSpace || store.showSearch { hideDrawer() }
            else {
                let work = DispatchWorkItem { [weak self] in self?.hideDrawer() }
                pendingClose = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: work)
            }
        }
        if store.showSearch && !store.locked {
            if !showingCommand {
                showingCommand = true; commandPrevious = NSApp.keyWindow
                command.contentView = NSHostingView(rootView: AavaCommandBar(store: store).ignoresSafeArea())
                attach(command); command.makeKey()
            } else { attach(command); if !command.isKeyWindow { command.makeKey() } }
        } else if showingCommand {
            showingCommand = false; parent.removeChildWindow(command); command.orderOut(nil); command.contentView = nil
            if !store.hasPanel {
                if let previous = commandPrevious, previous.isVisible { previous.makeKey() } else { parent.makeKey() }
            }
            commandPrevious = nil
        }
        let notifications = store.notifications
        if store.locked || changedSpace || store.showSearch || offersLink {
            pendingToastClose?.cancel(); toast.orderOut(nil); parent.removeChildWindow(toast)
        } else if notifications.queue.items.isEmpty {
            if pendingToastClose == nil, toast.isVisible {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.store.notifications.queue.items.isEmpty { self.toast.orderOut(nil); self.parent?.removeChildWindow(self.toast) }
                    self.pendingToastClose = nil
                }
                pendingToastClose = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        } else {
            pendingToastClose?.cancel(); pendingToastClose = nil
            let p = notifications.preferences.position
            let width: CGFloat = 376, height: CGFloat = notifications.stackHeight
            let x = p.isCenter ? frame.midX - width / 2 : p.isLeft ? frame.minX + 16 : frame.maxX - width - 16
            let topInset: CGFloat = store.hasPanel ? AavaGeometry.frameInset + AavaGeometry.drawerHeaderHeight : 44
            let y = p.isTop ? frame.maxY - height - topInset : frame.minY + 16
            toast.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            attach(toast)
        }
    }
    private func hideDrawer() {
        guard !store.hasPanel else { return }
        parent?.removeChildWindow(drawer); drawer.orderOut(nil)
        if !store.showSearch, let previous = previouslyFocused, previous.isVisible { previous.makeKey() }
        else { parent?.makeKey() }
        previouslyFocused = nil
    }
    private func close() {
        if let prompt = store.prompts.first { store.resolvePrompt(prompt, allow: false) }
        else { store.dismissPanels() }
    }
    deinit { if let linkKeyboardMonitor { NSEvent.removeMonitor(linkKeyboardMonitor) } }
}

private struct AavaDrawer: View {
    @ObservedObject var store: MacStore
    @ObservedObject var state: AavaSurfaceState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var drag: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.8, geometry.size.width - 2 * AavaGeometry.drawerInset)
            ZStack(alignment: .trailing) {
                Color.black.opacity(contrast == .increased ? 0.32 : 0.18)
                    .opacity(state.visible ? max(0, 1 - drag / width) : 0)
                    .contentShape(Rectangle()).onTapGesture(perform: state.close)
                    .accessibilityHidden(true)
                AavaPanelRouter(store: store, closeAction: state.close)
                    .frame(width: width).background { AavaChromeMaterial(space: store.space, isDrawer: true) }
                    .overlay(alignment: .leading) {
                        Capsule().fill(AavaSurfaceColors.ink.opacity(0.28)).frame(width: 4, height: 32)
                            .frame(width: 20, height: 96).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                                let x = value.translation.width
                                drag = x >= 0 ? x : (x * width * 0.55) / (width + 0.55 * abs(x))
                            }.onEnded { value in
                                if value.translation.width > width * 0.3 || value.predictedEndTranslation.width > width * 0.5 { state.close() }
                                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                            })
                            .accessibilityLabel("Drawer handle. Drag right to close.")
                            .accessibilityAddTraits(.isButton).accessibilityAction { state.close() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: AavaGeometry.drawerRadius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: AavaGeometry.drawerRadius, style: .continuous).strokeBorder(AavaSurfaceColors.ink.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 1) }
                    .padding(AavaGeometry.drawerInset)
                    .offset(x: reduceMotion ? 0 : (state.visible ? drag : width + 2 * AavaGeometry.drawerInset))
                    .opacity(state.visible ? 1 : 0)
            }.clipShape(RoundedRectangle(cornerRadius: AavaGeometry.frameRadius, style: .continuous))
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9), value: state.visible)
                .onExitCommand(perform: state.close)
                .onChange(of: state.visible) { _, _ in drag = 0 }
        }.environment(\.colorScheme, store.space.theme.darkText ? .light : .dark)
    }
}
