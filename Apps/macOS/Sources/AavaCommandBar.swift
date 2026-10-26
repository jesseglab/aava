import SwiftUI

struct AavaCommandBar: View {
    @ObservedObject var store: MacStore
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.opacity(0.10).contentShape(Rectangle()).onTapGesture { store.showSearch = false }.accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        SiteIcon(store: store, url: store.commandResults.first?.url)
                        AddressField(text: $store.address, submit: { store.commitCommand() }, move: store.moveCommand, cancel: { store.showSearch = false }).frame(height: 24)
                    }.padding(.horizontal, 14).padding(.vertical, 12)
                    Rectangle().fill(AavaSurfaceColors.ink.opacity(0.10)).frame(height: 1).padding(.horizontal, 10)
                    VStack(spacing: 2) {
                        ForEach(Array(store.commandResults.enumerated()), id: \.element.id) { index, result in
                            CommandRow(store: store, result: result, selected: index == store.commandIndex) { store.commandIndex = index; store.commitCommand(result) }
                                .onHover { if $0 { store.commandIndex = index } }
                        }
                    }.padding(6)
                    HStack(spacing: 9) {
                        Button { store.copyURL(); store.showSearch = false } label: { HStack(spacing: 10) { Image(systemName: "link"); Text("Copy URL") } }.buttonStyle(AavaHoverButton(inset: 6)).disabled(store.currentURL == nil)
                        Spacer()
                        Text("↑ ↓ select   ↵ open   esc close").font(.system(size: 10)).foregroundStyle(AavaSurfaceColors.secondary)
                    }.font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 10)
                }.frame(width: min(560, geometry.size.width - 48))
                    .background { AavaChromeMaterial(space: store.space, isDrawer: true, cornerRadius: AavaGeometry.surfaceRadius) }
                    .overlay { RoundedRectangle(cornerRadius: AavaGeometry.surfaceRadius, style: .continuous).strokeBorder(AavaSurfaceColors.ink.opacity(0.12), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
                    .padding(.top, max(52, min(110, geometry.size.height * 0.13)))
            }.foregroundStyle(AavaSurfaceColors.ink).environment(\.colorScheme, store.space.theme.darkText ? .light : .dark).environment(\.aavaSurfaceControls, true).tint(AavaSurfaceColors.accent).buttonStyle(AavaHoverButton())
        }.onExitCommand { store.showSearch = false }.onChange(of: store.address) { _, _ in store.commandIndex = 0 }
    }
}
private struct CommandRow: View {
    @ObservedObject var store: MacStore
    let result: CommandResult
    let selected: Bool
    let perform: () -> Void
    var body: some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                if result.kind == .action { Image(systemName: "command").font(.system(size: 12)).frame(width: 17) }
                else if result.kind == .navigate && result.url?.host == "duckduckgo.com" { Image(systemName: "magnifyingglass").font(.system(size: 12)).frame(width: 17) }
                else { SiteIcon(store: store, url: result.url) }
                Text(result.title).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 5)
                Text(result.detail).font(.system(size: 10)).opacity(0.65).lineLimit(1)
                if selected { Image(systemName: "return").font(.system(size: 10)).frame(width: 18, height: 18).background(AavaSurfaceColors.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 4)) }
            }.padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(selected ? AavaSurfaceColors.accent.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: AavaGeometry.insetRadius(AavaGeometry.surfaceRadius, by: 6)))
            .accessibilityLabel(result.title + ", " + result.detail).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
