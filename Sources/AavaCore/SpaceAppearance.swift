import Foundation

public struct SpacePreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let theme: SpaceTheme
    public static let all: [SpacePreset] = [
        .init(id: "tide", name: "Tide", theme: .tide),
        .init(id: "lagoon", name: "Lagoon", theme: .init(top: "73B7BC", bottom: "C8E5D9")),
        .init(id: "reef", name: "Reef", theme: .init(top: "D89586", bottom: "F2D3B0")),
        .init(id: "kelp", name: "Kelp", theme: .init(top: "244B49", bottom: "5F8271", darkText: false)),
        .init(id: "glacier", name: "Glacier", theme: .init(top: "A5BDD4", bottom: "E5EDF3")),
        .init(id: "forest", name: "Forest", theme: .init(top: "304B39", bottom: "64765B", darkText: false)),
        .init(id: "moss", name: "Moss", theme: .sage),
        .init(id: "dune", name: "Dune", theme: .init(top: "CBB394", bottom: "F0E4CD")),
        .init(id: "clay", name: "Clay", theme: .init(top: "B78572", bottom: "E2BFA7")),
        .init(id: "basalt", name: "Basalt", theme: .init(top: "363C44", bottom: "737981", darkText: false))
    ]
}
public struct BackgroundAsset: Codable, Equatable, Sendable {
    public var filename: String
    public var displayName: String
    public var animated: Bool
    public init(filename: String, displayName: String, animated: Bool) { self.filename = filename; self.displayName = displayName; self.animated = animated }
    public var validFilename: Bool {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && UUID(uuidString: String(parts[0])) != nil && ["gif", "png", "jpg", "heic", "webp", "tiff"].contains(String(parts[1]))
    }
}
public struct SpaceAppearance: Codable, Equatable, Sendable {
    public var transparency: Double
    public var noise: Double
    public var background: BackgroundAsset?
    public init(transparency: Double = 0, noise: Double = 0, background: BackgroundAsset? = nil) {
        self.transparency = transparency; self.noise = noise; self.background = background
    }
    public var safeTransparency: Double { transparency.isFinite ? min(0.85, max(0, transparency)) : 0 }
    public var safeNoise: Double { noise.isFinite ? min(1, max(0, noise)) : 0 }
}

public struct WheelColor: Equatable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double
    public init(hue: Double, saturation: Double, brightness: Double) { self.hue = hue; self.saturation = saturation; self.brightness = brightness }
    public init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        let r = Double((value >> 16) & 255) / 255, g = Double((value >> 8) & 255) / 255, b = Double(value & 255) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        brightness = high; saturation = high == 0 ? 0 : delta / high
        if delta == 0 { hue = 0 }
        else {
            let angle = high == r ? (g - b) / delta : high == g ? (b - r) / delta + 2 : (r - g) / delta + 4
            hue = ((angle / 6) + 1).truncatingRemainder(dividingBy: 1)
        }
    }
    public var hex: String {
        let h = ((hue.isFinite ? hue : 0).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let s = saturation.isFinite ? min(1, max(0, saturation)) : 0, v = brightness.isFinite ? min(1, max(0, brightness)) : 0
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let rgb: (Double, Double, Double)
        switch Int(h) { case 0: rgb = (c,x,0); case 1: rgb = (x,c,0); case 2: rgb = (0,c,x); case 3: rgb = (0,x,c); case 4: rgb = (x,0,c); default: rgb = (c,0,x) }
        return String(format: "%02X%02X%02X", Int(((rgb.0+m)*255).rounded()), Int(((rgb.1+m)*255).rounded()), Int(((rgb.2+m)*255).rounded()))
    }
}
