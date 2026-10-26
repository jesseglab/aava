import AppKit
import SwiftUI

struct SpaceSwipeRegion: NSViewRepresentable {
    let enabled: Bool
    let change: (Int) -> Void
    func makeNSView(context: Context) -> SwipeView { SwipeView() }
    func updateNSView(_ view: SwipeView, context: Context) { view.enabled = enabled; view.change = change }
    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }
    final class SwipeView: NSView {
        var enabled = true
        var change: ((Int) -> Void)?
        private var accumulator = SpaceSwipeAccumulator()
        private var monitor: Any?
        private func belongs(_ source: NSWindow?, to owner: NSWindow) -> Bool {
            guard let source else { return false }
            return source === owner || belongs(source.parent, to: owner)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                guard let self, self.enabled, let window = self.window, let source = event.window,
                      self.belongs(source, to: window), !self.isHiddenOrHasHiddenAncestor else { self?.accumulator.reset(); return event }
                let point = self.convert(window.convertPoint(fromScreen: source.convertPoint(toScreen: event.locationInWindow)), from: nil)
                guard self.bounds.contains(point) else { self.accumulator.reset(); return event }
                if event.type == .swipe {
                    guard abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 else { return event }
                    self.change?(event.deltaX < 0 ? 1 : -1); return nil
                }
                let scale = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
                var dx = event.scrollingDeltaX == 0 ? event.deltaX : event.scrollingDeltaX
                var dy = event.scrollingDeltaY == 0 ? event.deltaY : event.scrollingDeltaY
                if dx == 0 && event.modifierFlags.contains(.shift) { dx = dy; dy = 0 }
                let result = self.accumulator.consume(x: dx * scale, y: dy * scale, time: event.timestamp,
                    began: event.phase.contains(.began), ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
                    momentum: !event.momentumPhase.isEmpty, phased: !event.phase.isEmpty)
                if let step = result.step { self.change?(step) }
                return result.consumed ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }; accumulator.reset() }
        deinit { stop() }
    }
}

// A single compositor-driven color wash. No screenshot of the previous space,
// no second web view, and no per-frame browser layout or background decoding.
struct SpaceTide: NSViewRepresentable {
    let spaceID: UUID
    let theme: SpaceTheme
    let direction: Int
    let reducedMotion: Bool
    func makeNSView(context: Context) -> TideView { TideView() }
    func updateNSView(_ view: TideView, context: Context) { view.configure(id: spaceID, theme: theme, direction: direction, reduced: reducedMotion) }
    final class TideView: NSView {
        private let wash = CAGradientLayer()
        private let boundary = CAShapeLayer()
        private var previousID: UUID?
        private var previousTheme: SpaceTheme?
        private var size = CGSize.zero
        override init(frame: NSRect) {
            super.init(frame: frame); wantsLayer = true
            wash.startPoint = CGPoint(x: 0, y: 1); wash.endPoint = CGPoint(x: 1, y: 0)
            wash.mask = boundary; wash.opacity = 0
            layer?.addSublayer(wash)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            guard bounds.size != size else { return }; size = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            wash.frame = bounds; boundary.frame = bounds; wash.removeAllAnimations(); boundary.removeAllAnimations(); wash.opacity = 0
            CATransaction.commit()
        }
        func configure(id: UUID, theme: SpaceTheme, direction: Int, reduced: Bool) {
            defer { previousID = id; previousTheme = theme }
            guard let old = previousTheme, previousID != id, !reduced, bounds.width > 0 else {
                if reduced { wash.removeAllAnimations(); boundary.removeAllAnimations(); wash.opacity = 0 }
                return
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            wash.colors = [NSColor(Color(hex: old.top)).cgColor, NSColor(Color(hex: old.bottom)).cgColor]
            wash.frame = bounds; boundary.frame = bounds
            boundary.path = path(progress: 1, direction: direction)
            wash.opacity = 0
            CATransaction.commit()
            let wave = CAKeyframeAnimation(keyPath: "path")
            wave.values = (0...12).map { path(progress: CGFloat($0) / 12, direction: direction) }
            wave.duration = 0.32; wave.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 1; fade.duration = 0.32
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            boundary.add(wave, forKey: "tide"); wash.add(fade, forKey: "tide")
        }
        private func path(progress: CGFloat, direction: Int) -> CGPath {
            let w = bounds.width, h = bounds.height
            let bend = min(100, w * 0.12) * sin(progress * .pi)
            let x = w * (1 - progress)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: x, y: 0))
            p.addCurve(to: CGPoint(x: x, y: h), control1: CGPoint(x: x - bend, y: h * 0.28), control2: CGPoint(x: x + bend, y: h * 0.72))
            p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
            if direction < 0 { var transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0); return p.copy(using: &transform)! }
            return p
        }
    }
}

struct SpaceContentArrival: ViewModifier {
    let id: UUID
    let direction: Int
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        let noMotion = reduced, travel = CGFloat(direction) * 18
        return content.keyframeAnimator(initialValue: 0.0, trigger: id) { view, value in
            view.opacity(noMotion ? 1 : 1 - value * 0.28)
                .offset(x: noMotion ? 0 : travel * value)
        } keyframes: { _ in
            MoveKeyframe(1.0)
            CubicKeyframe(0.0, duration: 0.24)
        }
    }
}
