import AppKit
import CryptoKit
import SwiftUI

@MainActor final class FaviconCache {
    private let root: URL
    private let memory = NSCache<NSString, NSImage>()
    private var missing: Set<String> = []
    private var tints: [String: String] = [:]
    init(root: URL) { self.root = root; memory.countLimit = 128; memory.totalCostLimit = 4 * 1024 * 1024 }
    private func location(_ url: URL, profile: UUID) -> URL? {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host else { return nil }
        let origin = "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
        let hash = SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(profile.uuidString).appendingPathComponent(hash + ".png")
    }
    func image(_ url: URL?, profile: UUID) -> NSImage? {
        guard let url, let path = location(url, profile: profile) else { return nil }
        if let cached = memory.object(forKey: path.path as NSString) { return cached }
        guard !missing.contains(path.path) else { return nil }
        guard let image = NSImage(contentsOf: path), image.size.width <= 128, image.size.height <= 128 else {
            if missing.count >= 512 { missing.removeAll() }
            missing.insert(path.path); return nil
        }
        memory.setObject(image, forKey: path.path as NSString, cost: 32 * 32 * 4)
        return image
    }
    func tint(_ url: URL?, profile: UUID) -> String {
        guard let url, let path = location(url, profile: profile) else { return FaviconTint.fallback }
        if let value = tints[path.path] { return value }
        guard let icon = image(url, profile: profile), let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return FaviconTint.fallback }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16)); return true
        }
        let value = rendered ? FaviconTint.extract(pixels) : FaviconTint.fallback
        if tints.count >= 256 { tints.removeAll() }
        tints[path.path] = value; return value
    }
    func save(_ data: Data, url: URL, profile: UUID) {
        guard data.count <= 131072, let path = location(url, profile: profile), let image = NSImage(data: data), image.size.width <= 128, image.size.height <= 128 else { return }
        missing.remove(path.path); tints[path.path] = nil
        memory.setObject(image, forKey: path.path as NSString, cost: data.count)
        do {
            let folder = path.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: path, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            if files.count > 256 {
                let oldest = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
                for file in oldest.prefix(files.count - 256) { try? FileManager.default.removeItem(at: file) }
            }
        } catch { /* An unavailable icon cache must not interrupt browsing. */ }
    }
}

struct SiteIcon: View {
    @ObservedObject var store: MacStore
    let url: URL?
    var body: some View {
        Group {
            if let icon = store.favicon(url) { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit() }
            else if let host = url?.host {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .semibold)).frame(width: 17, height: 17)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: AavaGeometry.insetRadius(AavaGeometry.controlRadius, by: 4)))
            } else { Image(systemName: "globe").font(.system(size: 13)) }
        }.frame(width: 17, height: 17).accessibilityHidden(true)
    }
}

struct AavaHoverButton: ButtonStyle {
    var radius: CGFloat = AavaGeometry.controlRadius
    var inset: CGFloat = 0
    var active = false
    func makeBody(configuration: Configuration) -> some View { HoverBody(configuration: configuration, active: active, radius: radius, inset: inset) }
    private struct HoverBody: View {
        let configuration: ButtonStyle.Configuration
        let active: Bool
        let radius: CGFloat
        let inset: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        @Environment(\.aavaSurfaceControls) private var surfaceControls
        var body: some View {
            configuration.label.padding(inset).contentShape(RoundedRectangle(cornerRadius: radius))
                .background((surfaceControls ? AavaSurfaceColors.accent : Color.primary).opacity(!enabled ? 0 : configuration.isPressed ? 0.24 : active ? (hovered ? 0.22 : 0.18) : hovered ? 0.10 : 0), in: RoundedRectangle(cornerRadius: radius))
                .opacity(enabled ? 1 : 0.45)
                .animation(reduceMotion || configuration.isPressed ? nil : .easeOut(duration: 0.12), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: active)
                .accessibilityAddTraits(active ? .isSelected : [])
                .onHover { hovered = $0 }
        }
    }
}

struct SecondaryClick: NSViewRepresentable {
    var action: () -> Void
    func makeNSView(context: Context) -> ClickView { let view = ClickView(); view.action = action; return view }
    func updateNSView(_ view: ClickView, context: Context) { view.action = action }
    final class ClickView: NSView {
        var action: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown, bounds.contains(convert(point, from: superview)) else { return nil }
            return self
        }
        override func rightMouseDown(with event: NSEvent) { action?() }
    }
}

@MainActor enum ProviderIconCache {
    private static let images = NSCache<NSString, NSImage>()
    static func image(style: IconStyle, name: String) -> NSImage? {
        let key = "\(style.rawValue)-\(name)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("Icons/\(key).pdf")) else { return nil }
        images.countLimit = 64; images.setObject(image, forKey: key); return image
    }
}
