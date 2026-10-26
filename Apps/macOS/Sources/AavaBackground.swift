import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum AavaBackgroundFiles {
    static var repository: BackgroundRepository {
        let root = ProcessInfo.processInfo.environment["AAVA_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aava")
        return BackgroundRepository(root: root.appendingPathComponent("Backgrounds", isDirectory: true))
    }
}

struct AavaBackgroundMedia: NSViewRepresentable {
    let url: URL
    let animate: Bool
    func makeNSView(context: Context) -> BackgroundMediaView { BackgroundMediaView() }
    func updateNSView(_ view: BackgroundMediaView, context: Context) { view.configure(url: url, animate: animate) }
    static func dismantleNSView(_ view: BackgroundMediaView, coordinator: ()) { view.stop() }
}
final class BackgroundMediaView: NSView {
    private final class Frame: NSObject { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let firstFrames: NSCache<NSURL, Frame> = { let cache = NSCache<NSURL, Frame>(); cache.countLimit = 6; cache.totalCostLimit = 32 * 1024 * 1024; return cache }()
    private static let decoder = DispatchQueue(label: "app.aava.background-decode", qos: .userInitiated)
    private var generation = UUID()
    private var source: CGImageSource?
    private var file: URL?
    private var animated = false
    private var index = 0
    private var count = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill; layer?.masksToBounds = true
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.schedule() })
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { stop(); observers.forEach(NotificationCenter.default.removeObserver) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); schedule() }
    func stop() { timer?.invalidate(); timer = nil; generation = UUID() }
    func configure(url: URL, animate: Bool) {
        let changed = file != url, motionChanged = animated != animate
        guard changed || motionChanged else { return }
        stop(); file = url; animated = animate
        if changed {
            layer?.contents = nil; source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            count = source.map(CGImageSourceGetCount) ?? 0; index = 0
            if url.pathExtension.lowercased() != "gif" { count = min(1, count) }
        }
        if !animate { index = 0 }
        render()
    }
    private func render() {
        guard let source, count > 0, let file else { return }
        let token = UUID(); generation = token; let frameIndex = index
        if frameIndex == 0, let cached = Self.firstFrames.object(forKey: file as NSURL) {
            layer?.contents = cached.image; schedule(); return
        }
        // Decode bounded frames away from input handling; retain only a small
        // cache of first frames, never a complete animated GIF.
        Self.decoder.async { [weak self] in
            let image = CGImageSourceCreateThumbnailAtIndex(source, frameIndex, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceShouldCache: false] as CFDictionary)
            DispatchQueue.main.async {
                guard let self, self.generation == token, let image else { return }
                if frameIndex == 0 { Self.firstFrames.setObject(Frame(image), forKey: file as NSURL, cost: image.bytesPerRow * image.height) }
                self.layer?.contents = image; self.schedule()
            }
        }
    }
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard animated, count > 1, NSApp.isActive, window?.isVisible == true, window?.isMiniaturized == false, window?.occlusionState.contains(.visible) == true, let source else { return }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = max(0.05, (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }; self.index = (self.index + 1) % self.count; self.render()
        }
    }
}

struct BackgroundPasteTarget: NSViewRepresentable {
    let hovered: Bool
    let region: CGRect
    let paste: (NSPasteboard) -> Bool
    func makeNSView(context: Context) -> HoverPasteView { HoverPasteView() }
    func updateNSView(_ view: HoverPasteView, context: Context) { view.pasteContent = paste; view.hovered = hovered; view.region = region }
}
final class HoverPasteView: NSView {
    private static let targets = NSHashTable<HoverPasteView>.weakObjects()
    var hovered = false
    var region = CGRect.zero
    var pasteContent: ((NSPasteboard) -> Bool)?
    private var monitor: Any?
    override init(frame: NSRect) {
        super.init(frame: frame)
        Self.targets.add(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let window = self?.window, window.isKeyWindow else { return event }
            return Self.consumePaste(event, in: window) ? nil : event
        }
    }
    static func consumePaste(_ event: NSEvent, in window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        for target in targets.allObjects where target.window === window && !target.isHiddenOrHasHiddenAncestor {
            guard let content = window.contentView else { continue }
            var point = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            if !content.isFlipped { point.y = content.bounds.height - point.y }
            let inside = target.region.intersection(content.bounds).contains(point)
            if (inside || target.hovered), target.pasteContent?(NSPasteboard.general) == true { return true }
        }
        return false
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct BackgroundDropZone: View {
    @ObservedObject var store: MacStore
    @State private var targeted = false
    @State private var hovered = false
    @State private var pasteRegion = CGRect.zero
    private var asset: BackgroundAsset? { store.space.appearance?.background }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: asset == nil ? "photo.on.rectangle.angled" : "checkmark.circle").font(.system(size: 23, weight: .light))
            Text(asset?.displayName ?? "Make room for a view").font(.system(size: 13, weight: .medium)).lineLimit(1)
            Text("Drop an image or GIF, or hover here and press ⌘V").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            HStack {
                Button("Pick a file") { store.openPanel(.backgroundFile) }.buttonStyle(AavaHoverButton(inset: 9))
                Button("Paste image") { _ = store.pasteBackground(.general) }.buttonStyle(AavaHoverButton(inset: 9))
                if asset != nil { Button("Remove background") { store.removeBackground() }.buttonStyle(AavaHoverButton(inset: 9)) }
            }.font(.system(size: 12))
            if let message = store.backgroundError { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity).padding(20)
            .background(AavaSurfaceColors.field.opacity(targeted ? 1 : 0.4), in: RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius))
            .overlay { RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius).strokeBorder(AavaSurfaceColors.ink.opacity((targeted || hovered) ? 0.5 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4,4])) }
            .overlay { BackgroundPasteTarget(hovered: hovered, region: pasteRegion) { store.pasteBackground($0) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pasteRegion = $0 }
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                let scope = store.space.id
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        Task { @MainActor in if store.space.id == scope && !store.locked { store.importBackground(url) } }
                    }; return true
                }
                guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { return false }
                _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    guard let data else { return }; Task { @MainActor in if store.space.id == scope && !store.locked { store.importBackground(data, name: "Dropped image") } }
                }; return true
            }
    }
}

struct BackgroundFilePicker: View {
    @ObservedObject var store: MacStore
    @State private var path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures").path
    @State private var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    @State private var entries: [URL] = []
    @State private var error: String?
    private let supported: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif"]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelTitle("Choose your background", "Select an image or GIF. Aava keeps its own copy for this space.")
            HStack {
                ForEach(["Pictures", "Downloads", "Desktop"], id: \.self) { name in Button(name) { browse(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)) }.buttonStyle(AavaHoverButton(inset: 8)) }
                Spacer(); Button("Up") { browse(folder.deletingLastPathComponent()) }.buttonStyle(AavaHoverButton(inset: 8))
            }.font(.system(size: 12))
            HStack {
                TextField("Folder or image path", text: $path).textFieldStyle(.plain).onSubmit(go)
                Button("Go", action: go).buttonStyle(AavaHoverButton(inset: 8))
            }.padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.fieldRadius))
            if let error = error ?? store.backgroundError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(entries, id: \.self) { url in
                    let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    Button { if directory { browse(url) } else { select(url) } } label: {
                        HStack(spacing: 10) { Image(systemName: directory ? "folder" : "photo"); Text(url.lastPathComponent).lineLimit(1); Spacer(); Image(systemName: directory ? "chevron.right" : "plus").font(.system(size: 10)) }.font(.system(size: 13)).padding(12)
                    }.accessibilityLabel((directory ? "Open folder " : "Use background ") + url.lastPathComponent)
                }
            }
            if entries.isEmpty && error == nil { Text("No supported images here. Choose another folder or drop a file into Appearance.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary) }
            Button("Back to Appearance") { store.openSettings() }.buttonStyle(AavaHoverButton(inset: 10))
        }.onAppear { browse(folder) }
    }
    private func go() {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { browse(url) } else { select(url) }
    }
    private func browse(_ url: URL) {
        folder = url; path = url.path; error = nil
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).filter { file in
                (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || supported.contains(file.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch { entries = []; self.error = "This folder couldn’t be opened. Choose another folder or drop the file into Appearance." }
    }
    private func select(_ url: URL) { store.importBackground(url); if store.backgroundError == nil { store.openSettings() } }
}
