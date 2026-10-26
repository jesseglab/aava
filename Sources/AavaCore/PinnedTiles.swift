import Foundation

public struct PinnedTileStyle: Codable, Equatable, Sendable {
    public var span: Int
    public var name: String?
    public var tint: String?
    public init(span: Int = 1, name: String? = nil, tint: String? = nil) {
        self.span = span; self.name = name; self.tint = tint
    }
    public var columns: Int { span == 2 ? 2 : 1 }
    public var validTint: String? {
        guard let tint, tint.count == 6, tint.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return tint.uppercased()
    }
}
public struct PinnedTilePosition: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public let span: Int
}
public enum PinnedTilePacking {
    public static func positions(_ spans: [Int], columns: Int = 4) -> [PinnedTilePosition] {
        let columns = max(2, min(8, columns))
        var row = 0, column = 0
        return spans.map { value in
            let span = value == 2 ? 2 : 1
            if column + span > columns { row += 1; column = 0 }
            let position = PinnedTilePosition(row: row, column: column, span: span)
            column += span
            return position
        }
    }
}
public enum FaviconTint {
    public static let fallback = "A4AAFF"
    /// Reads a small premultiplied RGBA sample. Ignore transparent and neutral pixels;
    /// select a dominant hue before averaging, so opposing brand colors do not turn muddy.
    public static func extract(_ rgba: [UInt8]) -> String {
        guard rgba.count.isMultiple(of: 4) else { return fallback }
        var buckets = Array(repeating: (r: 0.0, g: 0.0, b: 0.0, weight: 0.0), count: 12)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Double(rgba[offset + 3]) / 255
            guard alpha > 0.15 else { continue }
            let rgb = (0..<3).map { min(1, Double(rgba[offset + $0]) / 255 / alpha) }
            let high = rgb.max()!, low = rgb.min()!, delta = high - low
            guard high > 0.12, delta / high > 0.18 else { continue }
            var hue: Double
            if high == rgb[0] { hue = (rgb[1] - rgb[2]) / delta }
            else if high == rgb[1] { hue = (rgb[2] - rgb[0]) / delta + 2 }
            else { hue = (rgb[0] - rgb[1]) / delta + 4 }
            hue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
            let bucket = min(11, Int(hue * 12)), weight = alpha * pow(delta / high, 2)
            buckets[bucket].r += rgb[0] * weight; buckets[bucket].g += rgb[1] * weight
            buckets[bucket].b += rgb[2] * weight; buckets[bucket].weight += weight
        }
        guard let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 0 else { return fallback }
        return [best.r, best.g, best.b].map { String(format: "%02X", Int(($0 / best.weight * 255).rounded())) }.joined()
    }
}
