import SwiftUI

struct AavaRootView: View {
    @ObservedObject var store: MacStore
    private var covered: Bool { store.showOnboarding }
    var body: some View {
        Group {
            if store.showOnboarding {
                AavaOnboardingView(store: store)
            } else { AavaBrowserView(store: store) }
        }
        .onAppear { AavaEngineOverlay(covered) }
        .onChange(of: covered) { _, visible in AavaEngineOverlay(visible) }
    }
}

struct AavaOnboardingView: View {
    @ObservedObject var store: MacStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ObservedObject private var mini = MiniControl.shared
    private let titles = ["Welcome", "Bring your places", "Make it yours", "Feels familiar", "New in Aava", "Room for your AI", "Ready to browse"]
    private var step: Int { store.onboarding.step }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 9) { AavaMark(color: AavaBrand.deep).frame(width: 28, height: 28); Text("aava").font(.system(size: 19, weight: .medium, design: .rounded)).tracking(-0.7) }
                    Spacer()
                    Button("Skip setup") { store.finishOnboarding() }.font(.system(size: 12)).foregroundStyle(AavaBrand.secondary)
                        .help("Go straight to the browser. Replay setup from Help at any time.")
                }.padding(.top, 36).padding(.horizontal, 42)
                ScrollView(.vertical) {
                HStack(spacing: geometry.size.width < 1000 ? 28 : 44) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(step == 0 ? "A BROWSER BY GEEKLAB" : "0\(step + 1) / \(titles[step].uppercased())")
                            .font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(AavaBrand.secondary).padding(.bottom, 22)
                        content.id(step).transition(.opacity)
                        Spacer(minLength: 24)
                        HStack(spacing: 18) {
                            if step > 0 { Button("Back") { move(forward: false) }.foregroundStyle(AavaBrand.secondary).font(.system(size: 13)) }
                            Button(step == 6 ? "Start browsing" : step == 0 ? "Make yourself at home" : "Continue") {
                                if step == 6 { store.finishOnboarding() } else { move(forward: true) }
                            }.buttonStyle(AavaPrimaryButton()).keyboardShortcut(.defaultAction)
                        }
                    }.frame(width: min(430, geometry.size.width * 0.4), height: 480, alignment: .topLeading)
                    artwork.frame(maxWidth: .infinity).frame(height: 480)

                }.padding(.horizontal, geometry.size.width < 1000 ? 32 : 52).padding(.vertical, geometry.size.height < 640 ? 26 : 60)
                }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
                HStack {
                    HStack(spacing: 7) {
                        ForEach(0..<OnboardingState.stepCount, id: \.self) { index in
                            Capsule().fill(index == step ? AavaBrand.deep : AavaBrand.deep.opacity(0.15)).frame(width: index == step ? 22 : 6, height: 6)
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel("Step \(step + 1) of \(OnboardingState.stepCount), \(titles[step])")
                    Spacer()
                    Text("Room to browse.").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary)
                }.padding(.horizontal, 42).padding(.bottom, 28)
            }
            .foregroundStyle(AavaBrand.deep).background(AavaBrand.salt)
            .clipShape(RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius, style: .continuous)).padding(AavaGeometry.frameInset).background(AavaBrand.air).clipShape(RoundedRectangle(cornerRadius: AavaGeometry.frameRadius, style: .continuous))
            .environment(\.colorScheme, .light).buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { appeared = true } }
        }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            Text("A calmer\nweb ahead.").font(.system(size: 50, weight: .regular, design: .serif)).tracking(-1.7).lineSpacing(-1).fixedSize(horizontal: false, vertical: true)
            Text("Your places, your pace.").font(.system(size: 19, weight: .medium)).padding(.top, 25)
            Text("Keep the things you love close. Give work, life and everything between a space of their own.")
                .font(.system(size: 14)).lineSpacing(5).foregroundStyle(AavaBrand.secondary).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            Text("A short setup. No account needed.").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary).padding(.top, 24)
        case 1:
            heading("Your places.\nA fresh start.")
            paragraph("Bring over your Arc spaces, pinned tabs, Favorites and folders. You’ll choose what to keep before anything is imported.")
            Button { store.previewArcImport() } label: {
                HStack(spacing: 10) { Image(systemName: "square.and.arrow.down"); Text("Import from Arc"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 13, weight: .medium)).padding(16).background(AavaBrand.air.opacity(0.65), in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
            }.padding(.top, 25)
            if store.onboardingImportedCount > 0 {
                Label("\(store.onboardingImportedCount) spaces imported", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Color(hex: "346951")).padding(.top, 12)
            } else {
                Text("Prefer a clean slate? Continue without importing.").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary).padding(.top, 12)
            }
            Text("Arc stays unchanged. Each space has separate sign-ins; cookies and passwords aren’t copied.").font(.system(size: 11)).lineSpacing(3).foregroundStyle(AavaBrand.secondary).padding(.top, 20)
        case 2:
            heading("A space that\nfeels like you.")
            paragraph(store.locked ? "This space is locked. Unlock it in the browser to change its appearance." : "Choose the mood for \(store.space.name). Every space keeps its own colors, icons and sign-ins.")
            if !store.locked {
                HStack(spacing: 12) {
                    themeChoice("Tide", .tide); themeChoice("Dusk", .dusk); themeChoice("Apricot", .apricot); themeChoice("Sage", .sage)
                }.padding(.top, 24)
                HStack(spacing: 9) {
                    ForEach(["🌊", "🌙", "🍑", "🌿", "🪐"], id: \.self) { emoji in
                        Button { store.spaceEmoji(emoji) } label: {
                            Text(emoji).font(.system(size: 20)).frame(width: 38, height: 38)
                                .background(store.space.emoji == emoji ? AavaBrand.air : .clear, in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
                        }.accessibilityLabel("Use \(emoji) for this space").accessibilityAddTraits(store.space.emoji == emoji ? .isSelected : [])
                    }
                }.padding(.top, 18)
                HStack(spacing: 5) {
                    ForEach(IconStyle.allCases, id: \.self) { style in
                        Button { store.icons(style) } label: {
                            Text(style.title).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 32)
                                .foregroundStyle(store.space.iconStyle == style ? AavaBrand.salt : AavaBrand.deep)
                                .background(store.space.iconStyle == style ? AavaBrand.deep : AavaBrand.air.opacity(0.45), in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
                        }.accessibilityLabel("\(style.title) sidebar icons").accessibilityAddTraits(store.space.iconStyle == style ? .isSelected : [])
                    }
                }.padding(.top, 18)
            }
        case 3:
            heading("Your habits.\nRight at home.")
            paragraph("Coming from Arc? The places you reach for are already here.")
            feature("sidebar.left", "Spaces in the sidebar", "Switch with the emoji row. Each space keeps its own tabs, saved places and look.")
            feature("pin", "Keep your favorites close", "Top pins, saved tabs and nested folders stay put. Ordinary tabs live below them.")
            feature("command", "The shortcuts you know", "⌘ T finds a page or tab. ⌘ L changes the address. ⌘ Y opens history and the archive.")
        case 4:
            heading("A few things\nto make yours.")
            paragraph("Familiar foundations. A little more control over your space.")
            feature("lock", "Separate sign-ins. Optional locks.", "Spaces keep separate website sessions. Add a PIN lock and choose when it locks again in Appearance. A PIN is a screen lock, not disk encryption.")
            feature("paintpalette", "More ways to make it yours", "Colors, glass, grain, images and GIFs. Resize the sidebar; give a wide pin its own name and tint.")
            feature("tray", "Less tending to tabs", "Tidy groups tabs by site. Clean moves ordinary tabs to the archive. Add a GitHub live folder for pull requests grouped by repository.")
        case 5:
            heading("Your AI works.\nYou keep browsing.")
            paragraph("Mini is a separate, temporary browser for an AI tool on this Mac. Your everyday tabs and sign-ins stay yours.")
            feature("eye", "Watch, take over, or stop", "Watch its page without changing yours. Take over pauses AI commands. Stop discards Mini’s temporary session.")
            Button(mini.copied ? "Prompt copied" : mini.running ? "Copy control prompt" : "Start Mini & copy prompt") { mini.copyPrompt() }
                .buttonStyle(AavaPrimaryButton()).padding(.top, 22)
            Button("Open Mini controls ↗") { mini.show() }.font(.system(size: 12, weight: .medium)).padding(.top, 14)
            Text("Paste the prompt into Codex or another tool with local command access and Python 3. Add your task. A chat-only AI cannot connect.").font(.system(size: 11)).lineSpacing(3).foregroundStyle(AavaBrand.secondary).padding(.top, 16)
            if mini.running && mini.paused { Text("Mini is paused. Open Mini controls to resume AI access.").font(.caption).foregroundStyle(AavaBrand.secondary).padding(.top, 8) }
        default:
            heading("A little more\nspace. All yours.")
            paragraph("Your sidebar keeps the important things close. Everything else gets room to breathe.")
            VStack(alignment: .leading, spacing: 13) {
                shortcut("⌘ L", "Go anywhere")
                shortcut("⌘ D", "Save a page to your sidebar")
                shortcut("⌘ ⇧ L", "Lock your private spaces")
            }.padding(.top, 22)
            Button("Make Aava your default browser…") { store.setDefault() }.font(.system(size: 12, weight: .medium)).underline().padding(.top, 26)
            Text("Optional. You can do this later from the Aava menu.").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary).padding(.top, 7)
            Text("Preview build · Keep Arc available while extension and live meeting compatibility are being validated.").font(.system(size: 10)).lineSpacing(3).foregroundStyle(AavaBrand.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 18)
        }
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 39, weight: .regular, design: .serif)).tracking(-1.3).fixedSize(horizontal: false, vertical: true)
    }
    private func paragraph(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).lineSpacing(4).foregroundStyle(AavaBrand.secondary).padding(.top, 17).fixedSize(horizontal: false, vertical: true)
    }
    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).lineSpacing(3).foregroundStyle(AavaBrand.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.top, 20)
    }
    private func shortcut(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 14) { Text(keys).font(.system(size: 11, weight: .medium)).frame(width: 52, alignment: .leading); Text(text).font(.system(size: 12)) }
    }
    private func themeChoice(_ name: String, _ theme: SpaceTheme) -> some View {
        Button { store.theme(theme) } label: {
            VStack(spacing: 7) {
                Circle().fill(LinearGradient(colors: [Color(hex: theme.top), Color(hex: theme.bottom)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 37, height: 37).overlay { if store.space.theme == theme { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.darkText ? AavaBrand.deep : AavaBrand.salt) } }
                Text(name).font(.system(size: 10))
            }.frame(width: 56)
        }.accessibilityLabel("\(name) theme").accessibilityAddTraits(store.space.theme == theme ? .isSelected : [])
    }
    @ViewBuilder private var artwork: some View {
        if step == 5 {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Image(systemName: "sparkle"); Text("A prompt with a private connection").font(.system(size: 13, weight: .semibold)) }
                ScrollView { Text(mini.prompt).font(.system(size: 11, design: .monospaced)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Text("Mini preview · One page. No shared logins, extensions, file access or camera/microphone.").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary)
            }.padding(24).background(AavaBrand.air, in: RoundedRectangle(cornerRadius: AavaGeometry.frameRadius))
        } else if step == 3 || step == 4 {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text(step == 3 ? "THE FAMILIAR PART" : "YOUR OWN LITTLE WORLD").font(.system(size: 10, weight: .semibold)).tracking(1); Spacer() }
                SpaceAppearancePreview(theme: store.space.theme, emoji: store.space.emoji, style: store.space.iconStyle)
                Text(step == 3 ? "Spaces · Pins · Folders · Quick search" : "Separate sessions · Personal style · Live folders").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary)
            }.padding(24).background(AavaBrand.air.opacity(0.45), in: RoundedRectangle(cornerRadius: AavaGeometry.frameRadius))
        } else if step == 2 {
            SpaceAppearancePreview(theme: store.space.theme, emoji: store.space.emoji, style: store.space.iconStyle)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: AavaGeometry.frameRadius).fill(AavaBrand.air)
                VStack(spacing: 24) {
                    Spacer()
                    AavaMark(animated: true).frame(width: 190, height: 190).id(step)
                    Text("aava").font(.system(size: 68, weight: .regular, design: .rounded)).tracking(-4).foregroundStyle(AavaBrand.deep)
                    Spacer()
                    HStack { Text(step == 1 ? "Saved places. Open horizons." : "ROOM TO BROWSE").font(.system(size: 10, weight: .medium)).tracking(1.2); Spacer(); Text("↗").font(.system(size: 18)) }.foregroundStyle(AavaBrand.secondary).padding(28)
                }
            }
        }
    }
    private func move(forward: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.moveOnboarding(forward: forward) }
    }
}

private struct SpaceAppearancePreview: View {
    let theme: SpaceTheme
    let emoji: String
    let style: IconStyle
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 4) { ForEach(0..<3) { _ in Circle().fill(AavaBrand.deep.opacity(0.18)).frame(width: 5, height: 5) } }
                Image(systemName: "magnifyingglass").font(.system(size: 11)).padding(.top, 10)
                Text("Saved").font(.system(size: 10, weight: .semibold))
                HStack(spacing: 6) { ProviderIcon(style: style, name: "folder", fallback: "folder", emoji: "📁"); Text("Ideas").font(.system(size: 10)) }
                HStack(spacing: 6) { ProviderIcon(style: style, name: "globe", fallback: "globe", emoji: "🌐"); Text("Today").font(.system(size: 10)) }
                Spacer()
                Text(emoji).font(.system(size: 20))
            }.frame(width: 78, alignment: .leading).padding(.vertical, 18).padding(.leading, 9)
            VStack(spacing: 16) {
                Spacer(); AavaMark().frame(width: 64, height: 64)
                Text("Room to\nbrowse.").font(.system(size: 26, weight: .regular, design: .serif)).multilineTextAlignment(.center).foregroundStyle(AavaBrand.deep)
                Spacer()
            }.frame(maxWidth: .infinity).background(AavaBrand.salt, in: RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius))
        }.padding(AavaGeometry.frameInset).foregroundStyle(theme.darkText ? AavaBrand.deep : AavaBrand.salt)
            .background(LinearGradient(colors: [Color(hex: theme.top), Color(hex: theme.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: AavaGeometry.frameRadius))
    }
}

struct AavaAboutView: View {
    var close: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            if let icon = AavaBrand.appIcon { Image(nsImage: icon).resizable().frame(width: 100, height: 100).accessibilityHidden(true) }
            Text("aava").font(.system(size: 44, weight: .regular, design: .rounded)).tracking(-2)
            Text("Room to browse.").font(.system(size: 14)).foregroundStyle(AavaSurfaceColors.secondary)
            Text("By Geeklab · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") preview").font(.system(size: 11)).foregroundStyle(AavaSurfaceColors.secondary)
            Text("A development preview. Chrome extensions and real Meet/Teams calls are still being validated.").font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(AavaSurfaceColors.secondary).frame(maxWidth: 290).padding(.vertical, 8)
            Button("Done", action: close).buttonStyle(AavaPrimaryButton()).keyboardShortcut(.defaultAction)
        }.padding(16).frame(maxWidth: .infinity).foregroundStyle(AavaSurfaceColors.ink)
    }
}
