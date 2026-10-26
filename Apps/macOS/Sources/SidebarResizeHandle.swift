import AppKit
import SwiftUI

// Pointer tracking and the tiny layer animation stay outside SwiftUI's page layout.
struct AavaSidebarResizeHandle: NSViewRepresentable {
    let width: Double
    let columns: Int
    let expanded: Bool
    let enabled: Bool
    let ink: Color
    let reduceMotion: Bool
    let resize: (Double) -> Void
    let commit: (Double) -> Void
    let reveal: () -> Void
    let collapse: () -> Void
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.sidebarWidth = width; view.columns = columns; view.expanded = expanded
        view.enabled = enabled; view.reduceMotion = reduceMotion
        view.resize = resize; view.commit = commit; view.reveal = reveal; view.collapse = collapse
        view.notch.backgroundColor = NSColor(ink).withAlphaComponent(0.48).cgColor
        view.needsLayout = true
        view.window?.invalidateCursorRects(for: view)
    }
    static func dismantleNSView(_ view: HandleView, coordinator: ()) { view.stopTracking() }

    final class HandleView: NSView {
        let notch = CALayer()
        var sidebarWidth: Double = 244
        var columns = 4
        var expanded = true
        var enabled = true
        var reduceMotion = false
        var resize: (Double) -> Void = { _ in }
        var commit: (Double) -> Void = { _ in }
        var reveal: () -> Void = {}
        var collapse: () -> Void = {}
        private var monitor: Any?
        private var pointerY: CGFloat?
        private var startX: CGFloat?
        private var startWidth: Double = 244
        private var proposedWidth: Double = 244
        private var hoverArea: NSTrackingArea?
        private var inactiveObserver: NSObjectProtocol?
        private var revealed = false
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        private var edgeX: CGFloat { expanded ? sidebarWidth + 12 : 4 }
        private var hitStrip: NSRect { NSRect(x: edgeX - (expanded ? 6 : 4), y: 62, width: expanded ? 10 : 8, height: max(0, bounds.height - 108)) }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            notch.bounds = CGRect(x: 0, y: 0, width: 3, height: 32)
            notch.cornerRadius = 1.5
            notch.opacity = 0
            layer?.addSublayer(notch)
            toolTip = "Drag to resize. Keep dragging left past half the minimum width to hide. Double-click to reset."
            setAccessibilityElement(true); setAccessibilityRole(.slider)
            setAccessibilityLabel("Sidebar width")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stopTracking()
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            inactiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setRevealed(false) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] event in
                self?.track(event); return event
            }
        }
        func stopTracking() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver); self.inactiveObserver = nil }
            startX = nil
            setRevealed(false)
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area); hoverArea = area
        }
        override func mouseExited(with event: NSEvent) { if startX == nil { setRevealed(false) } }
        override func mouseMoved(with event: NSEvent) { track(event) }
        private func setRevealed(_ value: Bool) {
            let show = enabled && NSApp.isActive && (value || startX != nil)
            guard show != revealed else { return }; revealed = show
            let old = notch.presentation()?.opacity ?? notch.opacity
            CATransaction.begin(); CATransaction.setDisableActions(true); notch.opacity = show ? 1 : 0; CATransaction.commit()
            guard !reduceMotion else { notch.removeAnimation(forKey: "reveal"); return }
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = old; fade.toValue = notch.opacity
            fade.duration = show ? 0.12 : 0.16; notch.add(fade, forKey: "reveal")
        }
        private func proximity(_ point: NSPoint) -> Bool {
            bounds.contains(point) && abs(point.x - edgeX) <= 24 && point.y >= 62 && point.y <= bounds.height - 46
        }
        private func belongs(_ source: NSWindow?, to owner: NSWindow) -> Bool {
            guard let source else { return false }
            if source === owner { return true }
            return belongs(source.parent, to: owner)
        }
        private func track(_ event: NSEvent) {
            guard enabled, let window, let source = event.window, belongs(source, to: window), NSApp.isActive else { setRevealed(false); return }
            let screen = source.convertPoint(toScreen: event.locationInWindow)
            let point = convert(window.convertPoint(fromScreen: screen), from: nil)
            let near = proximity(point); setRevealed(near)
            if near || startX != nil { moveNotch(to: point.y, animated: true) }
        }
        override func layout() {
            super.layout()
            notch.isHidden = !enabled
            if let window {
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                let near = proximity(point)
                if near { pointerY = point.y }
                setRevealed(near)
            }
            moveNotch(to: pointerY ?? bounds.midY, animated: false)
            setAccessibilityValue(expanded ? "\(Int(sidebarWidth)) points, \(columns) pinned columns" : "Hidden")
        }
        private func moveNotch(to y: CGFloat, animated: Bool) {
            let y = min(max(80, y), max(80, bounds.height - 64))
            let target = CGPoint(x: edgeX, y: y)
            guard target != notch.position else { return }
            let previous = notch.presentation()?.position ?? notch.position
            pointerY = y
            CATransaction.begin(); CATransaction.setDisableActions(true)
            notch.position = target
            CATransaction.commit()
            guard animated, !reduceMotion else {
                notch.removeAnimation(forKey: "follow"); notch.removeAnimation(forKey: "stretch"); return
            }
            let travel = CABasicAnimation(keyPath: "position")
            travel.fromValue = NSValue(point: previous); travel.toValue = NSValue(point: target)
            travel.duration = 0.24; travel.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.82, 0.24, 1)
            notch.add(travel, forKey: "follow")
            let stretch = min(1.65, 1 + abs(previous.y - y) / 130)
            let morph = CAKeyframeAnimation(keyPath: "transform.scale.y")
            morph.values = [notch.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat ?? 1, stretch, 1]
            morph.keyTimes = [0, 0.25, 1]; morph.duration = 0.32
            morph.timingFunctions = [.init(name: .easeOut), .init(name: .easeInEaseOut)]
            notch.add(morph, forKey: "stretch")
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled, hitStrip.contains(point) else { return nil }; return self
        }
        override func resetCursorRects() {
            if enabled { addCursorRect(hitStrip, cursor: startX != nil ? .closedHand : .openHand) }
        }
        override func mouseDown(with event: NSEvent) {
            if !expanded { reveal(); return }
            if event.clickCount == 2 { commit(SidebarSizing.defaultWidth); return }
            startX = event.locationInWindow.x
            setRevealed(true); NSCursor.closedHand.set()
            startWidth = sidebarWidth; proposedWidth = sidebarWidth
        }
        override func mouseDragged(with event: NSEvent) {
            guard let startX else { return }
            proposedWidth = startWidth + event.locationInWindow.x - startX
            if collapsePastThreshold() { return }
            NSCursor.closedHand.set()
            resize(proposedWidth)
            moveNotch(to: convert(event.locationInWindow, from: nil).y, animated: true)
        }
        override func mouseUp(with event: NSEvent) {
            guard let startX else { return }
            proposedWidth = startWidth + event.locationInWindow.x - startX
            if collapsePastThreshold() { return }
            self.startX = nil; commit(proposedWidth)
            let point = convert(event.locationInWindow, from: nil)
            setRevealed(proximity(point))
            if hitStrip.contains(point) { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            window?.invalidateCursorRects(for: self)
        }
        private func collapsePastThreshold() -> Bool {
            guard SidebarSizing.shouldCollapse(proposedWidth: proposedWidth) else { return false }
            startX = nil
            commit(SidebarSizing.minimumWidth)
            collapse()
            setRevealed(false)
            NSCursor.arrow.set()
            window?.invalidateCursorRects(for: self)
            return true
        }
        override func accessibilityPerformIncrement() -> Bool { if !expanded { reveal() }; commit(sidebarWidth + 16); return true }
        override func accessibilityPerformDecrement() -> Bool { commit(sidebarWidth - 16); return true }
    }
}
