import AppKit
import SwiftUI
import Darwin

@MainActor final class MiniControl: ObservableObject {
    static let shared = MiniControl()
    @Published var running = false
    @Published var ready = false
    @Published var paused = false
    @Published var watching = false
    @Published var url = "about:blank"
    @Published var loading = false
    @Published var notice = ""
    @Published var hasDialog = false
    @Published var image: NSImage?
    @Published var copied = false
    private var window: NSWindow?
    private var server: MiniSocketServer?
    private var replies: [String: (Data) -> Void] = [:]
    private var busy = false
    private var closing = false
    private var quitCompletion: (() -> Void)?
    private var session = ""
    private(set) var connection: URL?
    private var folder: URL?
    private var token = ""
    var prompt: String {
        AavaMiniGuide.prompt(cli: Bundle.main.resourceURL!.appendingPathComponent("aava-mini.py").path, connection: connection?.path)
    }
    func start() {
        guard !running else { return }
        guard !closing else { notice = "Finishing the previous session. Try again in a moment."; return }
        do {
            session = UUID().uuidString
            token = UUID().uuidString + UUID().uuidString
            let root = URL(fileURLWithPath: "/tmp/aava-mini-\(getuid())-\(session.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            folder = root
            let manifest = root.appendingPathComponent("connection.json")
            let socketPath = root.appendingPathComponent("control.sock").path
            let service = try MiniSocketServer(path: socketPath) { [weak self] data, respond in
                Task { @MainActor in self?.handle(data, respond: respond) }
            }
            server = service
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "socket": socketPath, "token": token, "session": session])
            try data.write(to: manifest, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
            connection = manifest; running = true; ready = false; paused = false; notice = ""; image = nil
            AavaMiniSetCallback { request, payload in
                let id = String(cString: request!), text = String(cString: payload!)
                DispatchQueue.main.async { MiniControl.shared.receive(id, text) }
            }
            AavaMiniStart()
        } catch { stop(); notice = "Mini couldn’t start: \(error.localizedDescription)" }
    }
    func stopForQuit(_ completion: @escaping () -> Void) {
        guard running || closing else { completion(); return }
        quitCompletion = completion; stop()
    }
    func stop() {
        closing = running || closing
        server?.stop(); server = nil
        for respond in replies.values { respond(Self.json(["ok": false, "error": "Mini session stopped."])) }
        replies.removeAll(); busy = false
        if let folder { try? FileManager.default.removeItem(at: folder) }
        connection = nil; folder = nil; token = ""; running = false; ready = false; watching = false; image = nil; notice = ""; hasDialog = false
        AavaMiniStop()
    }
    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 730), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Aava Mini · AI workspace"; panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 640, height: 560)
            panel.contentView = NSHostingView(rootView: MiniControlView(control: self))
            panel.center(); window = panel
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
                Task { @MainActor in MiniControl.shared.setWatching(false); MiniControl.shared.paused = true }
            }
        }
        window?.makeKeyAndOrderFront(nil)
        setWatching(true)
    }
    func setWatching(_ value: Bool) { watching = value; AavaMiniWatch(value && running) }
    func copyPrompt() {
        start(); guard running else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string); copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.copied = false }
    }
    private func receive(_ id: String, _ text: String) {
        guard let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if id == "_state" {
            if value["closed"] as? Bool == true { closing = false; let finish = quitCompletion; quitCompletion = nil; finish?() }
            ready = running && (value["ready"] as? Bool ?? false); url = value["url"] as? String ?? "about:blank"
            loading = value["loading"] as? Bool ?? false; hasDialog = value["dialog"] as? Bool ?? false
            if ready { AavaMiniWatch(watching) }
            if let message = value["notice"] as? String, !message.isEmpty { notice = message }
        } else if id == "_paint" {
            if watching, let encoded = value["png"] as? String, let png = Data(base64Encoded: encoded) { image = NSImage(data: png) }
        } else if let respond = replies.removeValue(forKey: id) { busy = false; respond(data) }
    }
    private func handle(_ data: Data, respond: @escaping (Data) -> Void) {
        guard running, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let supplied = value["token"] as? String, supplied == token,
              value["session"] as? String == session else { respond(Self.json(["ok": false, "error": "Unauthorized or expired Mini session."])); return }
        guard let method = value["method"] as? String else { respond(Self.json(["ok": false, "error": "Missing method."])); return }
        if method == "status" {
            respond(Self.json(["ok": true, "session": session, "ready": ready, "paused": paused, "watching": watching, "url": url, "loading": loading, "notice": notice, "dialog": hasDialog, "isolated": true])); return
        }
        guard !paused else { respond(Self.json(["ok": false, "error": "User takeover is active. Wait for the user to resume AI control."])); return }
        if method == "stop" { respond(Self.json(["ok": true])); DispatchQueue.main.async { self.stop() }; return }
        guard ["navigate", "snapshot", "click", "fill", "select", "scroll", "screenshot"].contains(method) else { respond(Self.json(["ok": false, "error": "Unsupported command. No arbitrary JavaScript or main-browser control is exposed."])); return }
        guard !busy else { respond(Self.json(["ok": false, "error": "Mini is busy. Inspect status; do not retry a submission blindly."])); return }
        guard ready else { respond(Self.json(["ok": false, "error": "Mini is starting. Check status."])); return }
        if method == "navigate", !(value["url"] is String) { respond(Self.json(["ok": false, "error": "URL must be a string."])); return }
        if ["click", "fill", "select"].contains(method), !(value["ref"] is String) { respond(Self.json(["ok": false, "error": "A fresh snapshot reference is required."])); return }
        if ["fill", "select"].contains(method), !(value["text"] is String) { respond(Self.json(["ok": false, "error": "Text must be a string."])); return }
        if method == "scroll", !(value["amount"] is NSNumber) { respond(Self.json(["ok": false, "error": "Scroll amount must be a number."])); return }
        busy = true
        let id = UUID().uuidString; replies[id] = respond
        var args = value; args.removeValue(forKey: "token"); args.removeValue(forKey: "session")
        let encoded = String(data: Self.json(args), encoding: .utf8)!
        AavaMiniCommand(id, encoded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, let pending = self.replies.removeValue(forKey: id) else { return }
            self.busy = false; pending(Self.json(["ok": false, "error": "Timed out; the action may have happened. Inspect a fresh snapshot before continuing."]))
        }
    }
    private static func json(_ value: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8) }
}

// One request per connection. Private UNIX socket: no TCP listener or CDP port.
private final class MiniReplyBox: @unchecked Sendable { let lock = NSLock(); var data = Data() }
private final class MiniSocketServer: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32
    private let path: String
    private let slots = DispatchSemaphore(value: 4)
    init(path: String, handler: @escaping (Data, @escaping (Data) -> Void) -> Void) throws {
        self.path = path
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(descriptor); throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in bytes.withUnsafeBytes { destination.copyBytes(from: $0) } }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(descriptor, 4) == 0 else { Darwin.close(descriptor); throw POSIXError(.EADDRINUSE) }
        chmod(path, 0o600)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self {
                self.lock.lock(); let fd = self.descriptor; self.lock.unlock(); if fd < 0 { return }
                let client = accept(fd, nil, nil); if client < 0 { return }
                guard self.slots.wait(timeout: .now()) == .success else { Darwin.close(client); continue }
                DispatchQueue.global(qos: .utility).async {
                    defer { Darwin.close(client); self.slots.signal() }
                    var timeout = timeval(tv_sec: 12, tv_usec: 0)
                    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    var noSignal: Int32 = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while data.count <= 65536 {
                        let count = recv(client, &buffer, buffer.count, 0); if count <= 0 { return }
                        data.append(contentsOf: buffer.prefix(count))
                        if data.contains(10) { break }
                    }
                    guard data.count <= 65536, let end = data.firstIndex(of: 10) else { return }
                    let semaphore = DispatchSemaphore(value: 0)
                    let box = MiniReplyBox()
                    handler(Data(data[..<end])) { response in
                        box.lock.lock(); box.data = response; box.lock.unlock(); semaphore.signal()
                    }
                    guard semaphore.wait(timeout: .now() + 13) == .success else { return }
                    box.lock.lock(); let packet = box.data + Data([10]); box.lock.unlock()
                    packet.withUnsafeBytes { bytes in
                        var offset = 0
                        while offset < bytes.count { let sent = send(client, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0); if sent <= 0 { break }; offset += sent }
                    }
                }
            }
        }
    }
    func stop() { lock.lock(); let fd = descriptor; descriptor = -1; lock.unlock(); if fd >= 0 { shutdown(fd, SHUT_RDWR); Darwin.close(fd); unlink(path) } }
    deinit { stop() }
}

struct MiniControlView: View {
    @ObservedObject var control: MiniControl
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { AavaMark(color: AavaSurfaceColors.accent).frame(width: 30, height: 30); Text("Aava Mini").font(.title2.bold()); Spacer(); Text(control.running ? (control.paused ? "You’re in control" : "AI workspace") : "Stopped").font(.caption) }
            Text("A separate, temporary browser. Your normal tabs and sign-ins stay yours.").font(.system(size: 13)).foregroundStyle(AavaSurfaceColors.secondary)
            HStack {
                Button(control.copied ? "Prompt copied" : control.running ? "Copy control prompt" : "Start Mini & copy prompt") { control.copyPrompt(); control.setWatching(true) }.buttonStyle(AavaPrimaryButton())
                if control.running {
                    Button(control.paused ? "Resume AI" : "Take over") { control.paused.toggle() }.buttonStyle(AavaHoverButton(inset: 10))
                    Button(control.watching ? "Hide preview" : "Watch") { control.setWatching(!control.watching) }.buttonStyle(AavaHoverButton(inset: 10))
                    Spacer(); Button("Stop Mini") { control.stop() }.buttonStyle(AavaHoverButton(inset: 10))
                }
            }
            Text(control.url).font(.system(size: 11, design: .monospaced)).lineLimit(1).foregroundStyle(AavaSurfaceColors.secondary)
            if control.watching, control.running {
                MiniPreview(image: control.image, interactive: control.paused).aspectRatio(1024.0/720, contentMode: .fit)
                    .background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { if control.image == nil { Text(control.ready ? "Waiting for a page" : "Starting Mini…").foregroundStyle(AavaSurfaceColors.secondary) } }
            } else {
                VStack(spacing: 10) { Image(systemName: "rectangle.inset.filled").font(.largeTitle); Text("Mini can work quietly in the background."); Text("Use Watch to inspect the same page without moving your normal browser.").font(.caption) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !control.notice.isEmpty { Text(control.notice).font(.caption).lineLimit(3) }
            if control.hasDialog {
                HStack { Text("Website message · resolve here").font(.caption); Button("Cancel") { AavaMiniDialog(false) }.buttonStyle(AavaHoverButton(inset: 8)); Button("Allow") { control.paused = true; AavaMiniDialog(true) }.buttonStyle(AavaHoverButton(inset: 8)) }
            }
            Text("Preview: one temporary page; no shared logins, extensions, downloads or camera/microphone. Cross-origin frames require manual takeover. Stopping discards this session.").font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
        }.padding(20).foregroundStyle(AavaSurfaceColors.ink).background(AavaSurfaceColors.surface).environment(\.colorScheme, .light).environment(\.aavaSurfaceControls, true)
    }
}
private struct MiniPreview: NSViewRepresentable {
    let image: NSImage?
    let interactive: Bool
    func makeNSView(context: Context) -> Preview { Preview() }
    func updateNSView(_ view: Preview, context: Context) { view.image = image; view.interactive = interactive; view.needsDisplay = true }
    final class Preview: NSView {
        var image: NSImage?
        var interactive = false
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { interactive }
        override func draw(_ dirtyRect: NSRect) { image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil) }
        private func point(_ event: NSEvent) -> NSPoint { let p = convert(event.locationInWindow, from: nil); return NSPoint(x: p.x / max(1,bounds.width)*1024, y: p.y/max(1,bounds.height)*720) }
        override func mouseDown(with event: NSEvent) { guard interactive else { return }; window?.makeFirstResponder(self); let p=point(event); AavaMiniPointer(Int32(p.x),Int32(p.y),0,0) }
        override func mouseUp(with event: NSEvent) { guard interactive else { return }; let p=point(event); AavaMiniPointer(Int32(p.x),Int32(p.y),1,0) }
        override func scrollWheel(with event: NSEvent) { guard interactive else { return }; let p=point(event); AavaMiniPointer(Int32(p.x),Int32(p.y),2,Int32(event.scrollingDeltaY*12)) }
        override func keyDown(with event: NSEvent) {
            guard interactive else { return }
            let codes: [UInt16:Int32] = [36:13,48:9,51:8,53:27,123:37,124:39,125:40,126:38]
            if let code=codes[event.keyCode] { AavaMiniKey("",code,false) }
            else if !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) { for scalar in (event.characters ?? "").utf16 { AavaMiniKey("",Int32(scalar),true) } }
        }
    }
}
