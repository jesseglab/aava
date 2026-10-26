import Foundation

public enum SidebarSizing {
    public static let defaultWidth: Double = 244
    public static let minimumWidth: Double = 160
    public static func shouldCollapse(proposedWidth: Double) -> Bool {
        proposedWidth.isFinite && proposedWidth < minimumWidth * 0.5
    }
    public static func width(_ requested: Double, container: Double) -> Double {
        let maximum = max(minimumWidth, min(420, floor(container - 24 - 420)))
        return min(maximum, max(minimumWidth, requested.isFinite ? requested.rounded() : defaultWidth))
    }
    public static func columns(width: Double) -> Int {
        guard width.isFinite else { return 4 }
        return max(2, min(6, Int(floor((width - 24 + 8) / 54))))
    }
}
