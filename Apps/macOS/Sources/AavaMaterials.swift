import AppKit
import SwiftUI

struct AavaChromeMaterial: View {
    let space: BrowserSpace
    var isDrawer = false
    var hideMedia = false
    var cornerRadius: CGFloat? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var radius: CGFloat { cornerRadius ?? (isDrawer ? AavaGeometry.drawerRadius : AavaGeometry.frameRadius) }
    private var preferences: SpaceAppearance { space.appearance ?? SpaceAppearance() }
    private var solid: Bool { reduceTransparency || contrast == .increased }
    private var mediaURL: URL? {
        guard !isDrawer, !hideMedia, let asset = preferences.background else { return nil }
        return AavaBackgroundFiles.repository.url(for: asset, profile: space.profileID)
    }
    var body: some View {
        ZStack {
            if isDrawer {
                if space.usesLiquidGlass && !solid { AavaNativeGlass(tint: NSColor(AavaSurfaceColors.surface), radius: radius, glass: true) }
                AavaSurfaceColors.surface.opacity(space.usesLiquidGlass && !solid ? 0.94 : 1)
                LinearGradient(colors: [Color(hex: space.theme.top), Color(hex: space.theme.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(solid ? 0 : 0.12)
            } else {
                let transparency = solid ? 0 : preferences.safeTransparency
                if !solid && (space.usesLiquidGlass || transparency > 0) {
                    AavaNativeGlass(tint: NSColor(Color(hex: space.theme.top)), radius: radius, glass: space.usesLiquidGlass).id(space.usesLiquidGlass)
                }
                LinearGradient(colors: [Color(hex: space.theme.top), Color(hex: space.theme.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(space.usesLiquidGlass && !solid ? 0.22 * (1 - transparency) : 1 - transparency)
                if let mediaURL {
                    AavaBackgroundMedia(url: mediaURL, animate: !reduceMotion).opacity(1 - transparency)
                }
                if preferences.safeNoise > 0 {
                    Image(nsImage: AavaNoise.image).resizable(resizingMode: .tile).blendMode(.softLight).opacity(preferences.safeNoise * 0.55)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)).allowsHitTesting(false)
    }
}

private enum AavaNoise {
    static let image: NSImage = {
        let width = 128, height = 128
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        var seed: UInt32 = 17
        if let pixels = bitmap.bitmapData {
            for i in 0..<(width * height) {
                seed = 1664525 &* seed &+ 1013904223
                let gray = UInt8((seed >> 24) & 255)
                pixels[i*4] = gray; pixels[i*4+1] = gray; pixels[i*4+2] = gray; pixels[i*4+3] = 255
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height)); image.addRepresentation(bitmap); return image
    }()
}

// One native material per surface, rather than a glass layer on every control.
private struct AavaNativeGlass: NSViewRepresentable {
    let tint: NSColor
    let radius: CGFloat
    let glass: Bool
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *), glass {
            let view = NSGlassEffectView()
            view.style = .regular
            view.contentView = NSView()
            return view
        }
        let view = NSVisualEffectView()
        view.material = .sidebar; view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.tintColor = tint.withAlphaComponent(0.35)
            glass.cornerRadius = radius
        } else {
            view.layer?.cornerRadius = radius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
    }
}
