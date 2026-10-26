import AppKit
import SwiftUI

struct AavaPendingLink: Identifiable {
    let id = UUID()
    let tab: UUID
    let space: UUID
    let source: URL
    let target: URL
    let domain: String
}

@MainActor final class AavaLinkChoices: ObservableObject {
    @Published private(set) var request: AavaPendingLink?
    @Published private(set) var countdown = LinkChoiceCountdown()
    @Published var hovered = false
    @Published var held = false
    @Published var remember = false { didSet { if remember { held = true } } }
    var available = false
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var valid: () -> Bool = { false }
    private var complete: (SameSiteLinkChoice, Bool) -> Void = { _, _ in }
    var paused: Bool { hovered || held || !available || !NSApp.isActive || NSWorkspace.shared.isVoiceOverEnabled }

    func present(_ link: AavaPendingLink, valid: @escaping () -> Bool, complete: @escaping (SameSiteLinkChoice, Bool) -> Void) {
        clear(); self.valid = valid; self.complete = complete
        request = link
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func checkContext() { if request != nil && !valid() { clear() } }
    private func tick() {
        guard request != nil else { return }
        guard valid() else { clear(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick; lastTick = now
        if countdown.advance(by: elapsed, paused: paused) { choose(.newTab, automatic: true) }
    }
    func choose(_ choice: SameSiteLinkChoice, automatic: Bool = false) {
        guard request != nil, valid() else { clear(); return }
        let action = complete, save = !automatic && remember
        clear(); action(choice, save)
    }
    func clear() {
        timer?.invalidate(); timer = nil; request = nil
        countdown = LinkChoiceCountdown(); hovered = false; held = false; remember = false
        valid = { false }; complete = { _, _ in }
    }
}

extension MacStore {
    func linkCandidate(tab identifier: String, source: String, target: String) -> AavaPendingLink? {
        guard !locked, !hasPanel, !showSearch, !showOnboarding,
              let id = UUID(uuidString: identifier), tab?.id == id,
              let from = URL(string: source), let to = URL(string: target),
              let domain = SameSiteLinks.sharedDomain(source: from, target: to),
              linkChoices.request == nil else { return nil }
        return AavaPendingLink(tab: id, space: space.id, source: from, target: to, domain: domain)
    }
    func offerLinkChoice(tab identifier: String, source: String, target: String) -> Bool {
        guard let link = linkCandidate(tab: identifier, source: source, target: target) else { return false }
        // Defer navigation until the Chromium popup callback has returned.
        if let choice = space.sameSiteLinkChoices?[link.domain] {
            DispatchQueue.main.async { [weak self] in self?.followLink(link, choice: choice, remember: false) }
        } else {
            linkChoices.present(link, valid: { [weak self] in self?.canFollowLink(link) == true }) { [weak self] choice, remember in
                self?.followLink(link, choice: choice, remember: remember)
            }
        }
        return true
    }
    func canFollowLink(_ link: AavaPendingLink) -> Bool {
        !locked && space.id == link.space && tab?.id == link.tab && tab?.url == link.source
    }
    private func followLink(_ link: AavaPendingLink, choice: SameSiteLinkChoice, remember: Bool) {
        guard canFollowLink(link) else { return }
        if remember {
            var choices = space.sameSiteLinkChoices ?? [:]; choices[link.domain] = choice
            state.spaces[state.currentSpaceIndex].sameSiteLinkChoices = choices
            saveNow()
        }
        if choice == .newTab { newTab(link.target) }
        else {
            // Navigate the original tab, retaining Chromium's unload protection.
            link.tab.uuidString.withCString { id in link.target.absoluteString.withCString { AavaEngineNavigate(id, $0) } }
        }
    }
    func forgetLinkChoice(_ domain: String) {
        guard !locked else { return }
        state.spaces[state.currentSpaceIndex].sameSiteLinkChoices?[domain] = nil; persist()
    }
}

struct AavaLinkChoiceCard: View {
    @ObservedObject var choices: AavaLinkChoices
    @ObservedObject var store: MacStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let request = choices.request {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(AavaSurfaceColors.ink.opacity(0.12), lineWidth: 2)
                        Circle().trim(from: 0, to: choices.countdown.remaining / 2)
                            .stroke(AavaSurfaceColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .linear(duration: 0.04), value: choices.countdown.remaining)
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    }.frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Another page on " + request.domain).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(choices.paused ? "Take your time. Choose where it opens." : "New tab in \(Int(ceil(choices.countdown.remaining)))s · Hover to pause")
                            .font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { choices.clear() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
                        .buttonStyle(AavaHoverButton()).accessibilityLabel("Cancel opening link")
                }
                Text(request.target.path.isEmpty ? "/" : request.target.path).font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    Button("New tab") { choices.choose(.newTab) }.buttonStyle(AavaPrimaryButton()).keyboardShortcut(.defaultAction)
                    Button("Replace current tab") { choices.choose(.replace) }.buttonStyle(AavaHoverButton(inset: 10))
                    Spacer(minLength: 0)
                }.font(.system(size: 12))
                Toggle("Remember for this domain in this space", isOn: $choices.remember)
                    .toggleStyle(.checkbox).font(.system(size: 11))
            }.padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { AavaChromeMaterial(space: store.space, isDrawer: true, cornerRadius: 16) }
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AavaSurfaceColors.ink.opacity(0.16), lineWidth: 1) }
                .foregroundStyle(AavaSurfaceColors.ink)
                .onHover { choices.hovered = $0 }
                .onExitCommand { choices.clear() }
                .environment(\.colorScheme, store.space.theme.darkText ? .light : .dark)
                .environment(\.aavaSurfaceControls, true)
                .accessibilityElement(children: .contain)
        }
    }
}

struct AavaLinkChoiceSettings: View {
    @ObservedObject var store: MacStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Links on the same domain").font(.system(size: 13, weight: .semibold))
            Text("When a site opens another page on its own domain, choose New tab or Replace. After two seconds, Aava opens a new tab. Hover to pause. Choices are saved only in this space; subdomains stay separate.")
                .font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            let choices = store.space.sameSiteLinkChoices ?? [:]
            ForEach(choices.keys.sorted(), id: \.self) { domain in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(domain).font(.system(size: 12, weight: .medium))
                        Text(choices[domain]?.title ?? "Ask each time").font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
                    }
                    Spacer()
                    Button("Ask again") { store.forgetLinkChoice(domain) }.buttonStyle(AavaHoverButton(inset: 8)).accessibilityLabel("Ask again for " + domain)
                }
            }
        }
    }
}
