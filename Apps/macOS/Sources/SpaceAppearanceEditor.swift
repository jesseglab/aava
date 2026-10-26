import AppKit
import SwiftUI

struct SpaceAppearanceEditor: View {
    @ObservedObject var store: MacStore
    private var appearance: SpaceAppearance { store.space.appearance ?? SpaceAppearance() }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("\(store.space.emoji)  \(store.space.name)").font(.system(size: 18, weight: .semibold)); Spacer(); Text("Just this space").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary) }
            SpacePrivacyControls(store: store)
            Divider()
            Text("From the sea to the earth").font(.system(size: 15, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(SpacePreset.all) { preset in
                    Button { store.theme(preset.theme) } label: {
                        VStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: AavaGeometry.insetRadius(AavaGeometry.surfaceRadius, by: 5)).fill(LinearGradient(colors: [Color(hex: preset.theme.top), Color(hex: preset.theme.bottom)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: 48).overlay { if store.space.theme == preset.theme { Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(preset.theme.darkText ? AavaSurfaceColors.ink : .white) } }
                            Text(preset.name).font(.system(size: 11))
                        }.padding(5)
                    }.buttonStyle(AavaHoverButton(radius: AavaGeometry.surfaceRadius, active: store.space.theme == preset.theme)).accessibilityLabel(preset.name + " preset")
                }
            }
            HStack(alignment: .top, spacing: 24) {
                AavaColorWheel(title: "Top color", hex: Binding(get: { store.space.theme.top }, set: { var theme = store.space.theme; theme.top = $0; store.theme(theme) }))
                AavaColorWheel(title: "Bottom color", hex: Binding(get: { store.space.theme.bottom }, set: { var theme = store.space.theme; theme.bottom = $0; store.theme(theme) }))
            }
            Divider()
            HStack {
                Text("Material").font(.system(size: 13, weight: .semibold)); Spacer()
                ForEach([false, true], id: \.self) { glass in
                    Button(glass ? "Liquid Glass" : "Solid") { store.liquidGlass(glass) }.font(.system(size: 12))
                        .buttonStyle(AavaHoverButton(inset: 10, active: store.space.usesLiquidGlass == glass)).accessibilityAddTraits(store.space.usesLiquidGlass == glass ? .isSelected : [])
                }
            }
            control("Transparency", value: Binding(get: { appearance.safeTransparency }, set: { store.appearance(transparency: $0) }), range: 0...0.85)
            control("Noise", value: Binding(get: { appearance.safeNoise }, set: { store.appearance(noise: $0) }), range: 0...1)
            Text("Texture stays still. Reduce Transparency keeps the frame solid; Reduce Motion pauses GIF backgrounds.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            Text("Background image or GIF").font(.system(size: 15, weight: .semibold))
            BackgroundDropZone(store: store)
            Toggle("Dark sidebar text", isOn: Binding(get: { store.space.theme.darkText }, set: { var theme = store.space.theme; theme.darkText = $0; store.theme(theme) })).toggleStyle(.switch).font(.system(size: 13))
            Text("Space icon").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 5) { ForEach(["🌊", "🐚", "🪸", "🏔️", "🏡", "💼", "🎨", "🌿"], id: \.self) { icon in
                Button { store.spaceEmoji(icon) } label: { Text(icon).font(.system(size: 20)).frame(width: 36, height: 36) }.buttonStyle(AavaHoverButton(active: store.space.emoji == icon))
            } }
            Text("Folder and interface icons").font(.system(size: 13, weight: .semibold))
            HStack { ForEach(IconStyle.allCases, id: \.self) { style in
                Button { store.icons(style) } label: { HStack { ProviderIcon(style: style, name: "folder", fallback: "folder", emoji: "📁"); Text(style.title) }.font(.system(size: 12)).padding(12) }.buttonStyle(AavaHoverButton(active: store.space.iconStyle == style))
            } }
        }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).fontWeight(.medium); Spacer(); Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().foregroundStyle(AavaSurfaceColors.secondary) }.font(.system(size: 12))
            Slider(value: value, in: range).tint(AavaSurfaceColors.accent).accessibilityLabel(title)
        }
    }
}

struct AavaColorWheel: View {
    let title: String
    @Binding var hex: String
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var brightness = 1.0
    private let diameter: CGFloat = 120
    private var current: String { WheelColor(hue: hue, saturation: saturation, brightness: brightness).hex }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.system(size: 12, weight: .medium)); Spacer(); Text("#" + hex).font(.system(size: 10, design: .monospaced)).foregroundStyle(AavaSurfaceColors.secondary) }
            ZStack {
                Circle().fill(AngularGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: diameter / 2))
                Circle().fill(.black.opacity(1 - brightness))
                Circle().strokeBorder(.white, lineWidth: 2).background(Circle().stroke(.black.opacity(0.45), lineWidth: 1)).frame(width: 12, height: 12)
                    .offset(x: cos(hue * 2 * .pi) * saturation * (diameter / 2 - 6), y: sin(hue * 2 * .pi) * saturation * (diameter / 2 - 6))
            }.frame(width: diameter, height: diameter).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(title)).onChanged { value in update(value.location) })
                .coordinateSpace(name: title)
                .accessibilityElement(children: .ignore).accessibilityLabel(title + " color wheel").accessibilityValue("Hue \(Int(hue * 360)) degrees")
                .accessibilityAdjustableAction { direction in hue = (hue + (direction == .increment ? 0.025 : -0.025) + 1).truncatingRemainder(dividingBy: 1); hex = current }
                .overlay { GeometryReader { proxy in Color.clear.onAppear { wheelWidth = proxy.size.width }.onChange(of: proxy.size.width) { _, width in wheelWidth = width } }.allowsHitTesting(false) }
            HStack { Text("Saturation"); Slider(value: $saturation, in: 0...1) { _ in }.onChange(of: saturation) { _, _ in hex = current }.accessibilityLabel(title + " saturation") }.font(.system(size: 10))
            HStack { Text("Brightness"); Slider(value: $brightness, in: 0...1).onChange(of: brightness) { _, _ in hex = current }.accessibilityLabel(title + " brightness") }.font(.system(size: 10))
        }.frame(maxWidth: .infinity).tint(AavaSurfaceColors.accent)
            .onAppear(perform: read).onChange(of: hex) { _, value in if current != value { read() } }
    }
    @State private var wheelWidth: CGFloat = 120
    private func update(_ point: CGPoint) {
        let dx = point.x - wheelWidth / 2, dy = point.y - diameter / 2
        hue = (atan2(dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
        saturation = min(1, sqrt(dx * dx + dy * dy) / (diameter / 2)); hex = current
    }
    private func read() {
        let c = WheelColor(hex: hex)
        hue = c.hue; saturation = c.saturation; brightness = c.brightness
    }
}

struct SpacePrivacyControls: View {
    @ObservedObject var store: MacStore
    @State private var mode: String?
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmation = ""
    private var settings: PrivateSpaceSettings { store.space.privacy ?? PrivateSpaceSettings() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Space privacy", systemImage: store.space.privacy == nil ? "lock.open" : "lock.fill").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Standard") { if store.space.privacy != nil { mode = "remove"; store.privateError = nil } }.font(.system(size: 12)).buttonStyle(AavaHoverButton(inset: 10, active: store.space.privacy == nil))
                Button("PIN locked") { if store.space.privacy == nil { store.beginPrivateSetup() } }.font(.system(size: 12)).buttonStyle(AavaHoverButton(inset: 10, active: store.space.privacy != nil))
            }
            if store.space.privacy != nil {
                Toggle("Stay on when switching spaces", isOn: Binding(get: { settings.stayOn ?? false }, set: { store.privatePreferences(stayOn: $0, minutes: settings.idleMinutes) })).toggleStyle(.switch).font(.system(size: 12))
                HStack {
                    Text("Lock after idle").font(.system(size: 12)); Spacer()
                    ForEach([15, 30, 60], id: \.self) { minutes in Button(minutes == 60 ? "1 hour" : "\(minutes) min") { store.privatePreferences(stayOn: settings.stayOn ?? false, minutes: minutes) }.font(.system(size: 12)).buttonStyle(AavaHoverButton(inset: 9, active: settings.idleMinutes == minutes)) }
                }
                HStack {
                    Button("Change PIN") { mode = "change"; store.privateError = nil }.buttonStyle(AavaHoverButton(inset: 8))
                    Button("Lock now") { store.lockCurrentSpace() }.buttonStyle(AavaHoverButton(inset: 8))
                }.font(.system(size: 12))
            } else { Text("Sign-ins and browsing data still stay separate from other spaces.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary) }
            if let mode {
                Text(mode == "remove" ? "Enter the current PIN to remove this space’s PIN lock. Its separate browser profile stays in place." : "Confirm the current PIN, then choose a new 6–12 digit PIN.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
                SecureField("Current PIN", text: $currentPIN).textFieldStyle(.plain).padding(10).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
                if mode == "change" {
                    SecureField("New PIN", text: $newPIN).textFieldStyle(.plain).padding(10).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
                    SecureField("Confirm new PIN", text: $confirmation).textFieldStyle(.plain).padding(10).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
                }
                HStack {
                    Button("Cancel") { reset() }.buttonStyle(AavaHoverButton(inset: 8))
                    Button(mode == "remove" ? "Remove PIN lock" : "Save PIN") {
                        let succeeded = mode == "remove" ? store.removePrivateLock(pin: currentPIN) : store.changePrivatePIN(current: currentPIN, new: newPIN, confirmation: confirmation)
                        currentPIN = ""; newPIN = ""; confirmation = ""; if succeeded { reset() }
                    }.buttonStyle(AavaPrimaryButton()).disabled(currentPIN.isEmpty || (mode == "change" && (!PINVerifier.isValid(newPIN) || newPIN != confirmation)))
                }
            }
            if let error = store.privateError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }.onDisappear { reset() }.onChange(of: store.space.id) { _, _ in reset() }
    }
    private func reset() { mode = nil; currentPIN = ""; newPIN = ""; confirmation = "" }
}
