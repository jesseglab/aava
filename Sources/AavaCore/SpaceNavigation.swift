import Foundation

public enum SpaceNavigation {
    public static func destination(current: Int, count: Int, step: Int) -> Int? {
        guard count > 1, current >= 0, current < count, step != 0 else { return nil }
        let offset = step % count
        return ((current + offset) % count + count) % count
    }
}

/// One deliberate horizontal movement per gesture. Vertical scrolling and the
/// momentum tail never trigger another space change.
public struct SpaceSwipeAccumulator {
    private var x = 0.0, y = 0.0
    private var decided = false
    private var momentumCaptured = false
    private var lastTime = -Double.infinity
    public init() {}
    public mutating func reset() { x = 0; y = 0; decided = false; momentumCaptured = false; lastTime = -.infinity }
    public mutating func consume(x dx: Double, y dy: Double, time: Double, began: Bool, ended: Bool, momentum: Bool, phased: Bool) -> (consumed: Bool, step: Int?) {
        guard !momentum else { return (momentumCaptured, nil) }
        if began || (!phased && time - lastTime > 0.22) { reset() }
        lastTime = time
        if ended { let captured = momentumCaptured; reset(); momentumCaptured = captured; return (captured, nil) }
        if decided { return (abs(x) > abs(y), nil) }
        x += dx; y += dy
        if abs(y) > 12 && abs(y) > abs(x) * 1.25 { decided = true; return (false, nil) }
        guard abs(x) > 12 && abs(x) > abs(y) * 1.35 else { return (false, nil) }
        momentumCaptured = true
        guard abs(x) >= 32 else { return (true, nil) }
        decided = true
        return (true, x < 0 ? 1 : -1)
    }
}
