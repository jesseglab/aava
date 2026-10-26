import AppKit
import SwiftUI

enum AavaGeometry {
    static let frameInset = CGFloat(AavaFrameInset)
    static let frameRadius = CGFloat(AavaFrameRadius)
    static let surfaceRadius = insetRadius(frameRadius, by: frameInset)
    static let controlRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 12
    static let drawerInset = frameInset * 2
    static let drawerRadius = insetRadius(surfaceRadius, by: frameInset)
    static let contentInset: CGFloat = 16
    static let drawerHeaderHeight: CGFloat = 48
    static let sidebarWidth: CGFloat = 244
    static let sidebarInset: CGFloat = 12
    static let sidebarToolbarHeight: CGFloat = 36
    static let sidebarToolbarTop: CGFloat = 4
    static let trafficLightCenterY = frameInset + sidebarToolbarTop + sidebarToolbarHeight / 2
    static func insetRadius(_ outer: CGFloat, by gap: CGFloat) -> CGFloat {
        CGFloat(AavaInsetRadius(Double(outer), Double(gap)))
    }
}

enum AavaBrand {
    static let deep = Color(hex: "262A36")
    static let salt = Color(hex: "F6F7FC")
    static let air = Color(hex: "E6E9F5")
    static let periwinkle = Color(hex: "A7B4FF")
    static let secondary = Color(hex: "606576")
    static let appIcon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand").flatMap(NSImage.init(contentsOf:))
    static let letterMark: NSImage? = Bundle.main.url(forResource: "LetterA", withExtension: "png", subdirectory: "Brand").flatMap(NSImage.init(contentsOf:))
}

// Surface colors resolve against each space's appearance, not the system theme.
enum AavaSurfaceColors {
    static let ink = adaptive("262A36", "F0F1F8")
    static let secondary = adaptive("606576", "B6BBCE")
    static let surface = adaptive("F6F7FC", "252938")
    static let field = adaptive("E9ECF7", "343849")
    static let accent = adaptive("525FAD", "A7B4FF")
    static let onAccent = adaptive("F6F7FC", "202434")
    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(Color(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light))
        })
    }
}
private struct AavaSurfaceControlsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var aavaSurfaceControls: Bool {
        get { self[AavaSurfaceControlsKey.self] }
        set { self[AavaSurfaceControlsKey.self] = newValue }
    }
}

struct AavaMark: View {
    var color: Color? = nil
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        Group {
            if let mark = AavaBrand.letterMark {
                Image(nsImage: mark)
                    .renderingMode(color == nil ? .original : .template)
                    .resizable().interpolation(.high)
                    .foregroundStyle(color ?? AavaBrand.periwinkle)
            } else {
                Text("A").font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(color ?? AavaBrand.periwinkle)
            }
        }.aspectRatio(1, contentMode: .fit)
            .scaleEffect(animated && !revealed && !reduceMotion ? 0.92 : 1)
            .offset(y: animated && !revealed && !reduceMotion ? 6 : 0)
            .opacity(animated && !revealed && !reduceMotion ? 0 : 1)
            .accessibilityHidden(true)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { revealed = true } }
    }
}

struct AavaPrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 22).frame(height: 42)
            .background(AavaSurfaceColors.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius))
            .foregroundStyle(AavaSurfaceColors.onAccent)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AavaStartPage: View {
    @ObservedObject var store: MacStore
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AavaMark().frame(width: 86, height: 86)
            Text("aava").font(.system(size: 76, weight: .regular, design: .rounded)).tracking(-5).foregroundStyle(AavaBrand.deep)
            Text("Room to browse.").font(.system(size: 16)).foregroundStyle(AavaBrand.secondary)
            Button { store.search() } label: {
                HStack(spacing: 28) { Text("Where to?"); Text("⌘ L").opacity(0.6) }
            }.buttonStyle(AavaPrimaryButton()).padding(.top, 12)
            Spacer()
            Text("\(store.space.emoji)  \(store.space.name)").font(.system(size: 11)).foregroundStyle(AavaBrand.secondary).padding(.bottom, 26)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AavaBrand.salt)
    }
}
