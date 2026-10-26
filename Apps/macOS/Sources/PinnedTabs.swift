import SwiftUI

private struct TileSpanKey: LayoutValueKey { static let defaultValue = 1 }
private struct PinnedGrid: Layout {
    let columns: Int
    static let gap: CGFloat = 8
    let tileHeight: CGFloat
    let rowGap: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = (PinnedTilePacking.positions(subviews.map { $0[TileSpanKey.self] }, columns: columns).last?.row ?? -1) + 1
        return CGSize(width: proposal.width ?? 220, height: max(0, CGFloat(rows) * (tileHeight + rowGap) - rowGap))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = max(0, (bounds.width - Self.gap * CGFloat(columns - 1)) / CGFloat(columns))
        let positions = PinnedTilePacking.positions(subviews.map { $0[TileSpanKey.self] }, columns: columns)
        for (index, position) in positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(position.column) * (cell + Self.gap), y: bounds.minY + CGFloat(position.row) * (tileHeight + rowGap)), anchor: .topLeading,
                proposal: ProposedViewSize(width: cell * CGFloat(position.span) + Self.gap * CGFloat(position.span - 1), height: tileHeight))
        }
    }
}
struct PinnedTabs: View {
    @ObservedObject var store: MacStore
    let ink: Color
    var columns: Int = 4
    private var tabs: [BrowserTab] { store.space.tabs.filter(\.pinned) }
    var heightBudget: CGFloat = 360
    private var rows: Int { (PinnedTilePacking.positions(tabs.map { $0.tile?.columns ?? 1 }, columns: columns).last?.row ?? -1) + 1 }
    private var rowGap: CGFloat { min(6, heightBudget / CGFloat(max(1, rows)) * 0.16) }
    private var tileHeight: CGFloat { min(38, max(1, (heightBudget - rowGap * CGFloat(max(0, rows - 1))) / CGFloat(max(1, rows)))) }
    private var height: CGFloat { max(0, CGFloat(rows) * (tileHeight + rowGap) - rowGap) }
    var body: some View {
        if !tabs.isEmpty {
            PinnedGrid(columns: columns, tileHeight: tileHeight, rowGap: rowGap) {
                ForEach(tabs) { tab in
                    PinnedTabTile(store: store, tab: tab, ink: ink, tileHeight: tileHeight).layoutValue(key: TileSpanKey.self, value: tab.tile?.columns ?? 1)
                }
            }.frame(height: height).accessibilityElement(children: .contain).accessibilityLabel("Pinned tabs")
        }
    }
}

private struct PinnedTabTile: View {
    @ObservedObject var store: MacStore
    let tab: BrowserTab
    let ink: Color
    let tileHeight: CGFloat
    @State private var hovered = false
    private var wide: Bool { tab.tile?.columns == 2 }
    private var radius: CGFloat { AavaGeometry.insetRadius(AavaGeometry.surfaceRadius, by: 4) }
    private var tint: Color { Color(hex: tab.tile?.validTint ?? store.faviconTint(tab.pinnedURL ?? tab.url)) }
    private var selected: Bool { store.tab?.id == tab.id }
    var body: some View {
        Button { store.dismissPanels(); store.select(tab.id) } label: {
            HStack(spacing: 8) {
                SiteIcon(store: store, url: tab.pinnedURL ?? tab.url)
                if wide { Text(tab.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail) }
            }.padding(.horizontal, wide ? 11 : 4).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(ink.opacity(selected ? 0.13 : 0.08))
                    if wide {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(LinearGradient(colors: [tint.opacity(0.36), tint.opacity(0.12), ink.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(ink.opacity(selected ? 0.22 : hovered ? 0.12 : 0), lineWidth: 1) }
                .overlay(alignment: .bottomTrailing) {
                    if store.callPolicy.capturing.contains(tab.id) { Circle().fill(.green).frame(width: 5, height: 5).padding(5).accessibilityLabel("Camera or microphone active") }
                }
        }.foregroundStyle(ink).buttonStyle(AavaHoverButton(radius: radius))
            .onHover { hovered = $0 }
            .overlay { SecondaryClick { store.openPanel(.tab(tab.id)) } }
            .help(tab.displayTitle + " · Right-click to customize")
            .accessibilityLabel(tab.displayTitle + ", pinned, " + (wide ? "2 columns" : "1 column"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: Text("Customize pinned tab")) { store.openPanel(.tab(tab.id)) }
    }
}
struct PinnedTileEditor: View {
    @ObservedObject var store: MacStore
    let id: UUID
    private var tab: BrowserTab? { store.space.tabs.first { $0.id == id } }
    private var style: PinnedTileStyle { tab?.tile ?? PinnedTileStyle() }
    private var automatic: String { store.faviconTint(tab?.pinnedURL ?? tab?.url) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pinned tile").font(.system(size: 14, weight: .semibold))
            HStack {
                ForEach([1, 2], id: \.self) { columns in
                    Button { var value = style; value.span = columns; store.tileStyle(id, value) } label: {
                        HStack(spacing: 7) { Image(systemName: columns == 1 ? "square" : "rectangle"); Text(columns == 1 ? "1 column" : "2 columns") }.font(.system(size: 12)).padding(11)
                    }.buttonStyle(AavaHoverButton(active: style.columns == columns)).accessibilityAddTraits(style.columns == columns ? .isSelected : [])
                }
            }
            if style.columns == 2 {
                Text("Name").font(.system(size: 12, weight: .medium))
                TextField(tab?.title ?? "Tab name", text: Binding(get: { style.name ?? "" }, set: { var value = style; value.name = $0; store.tileStyle(id, value) }))
                    .textFieldStyle(.plain).padding(12).background(AavaSurfaceColors.field, in: RoundedRectangle(cornerRadius: AavaGeometry.controlRadius)).accessibilityLabel("Pinned tab name")
                HStack {
                    Button("From favicon") { var value = style; value.tint = nil; store.tileStyle(id, value) }.buttonStyle(AavaHoverButton(inset: 10, active: style.validTint == nil))
                    Button("Custom color") { var value = style; value.tint = style.validTint ?? automatic; store.tileStyle(id, value) }.buttonStyle(AavaHoverButton(inset: 10, active: style.validTint != nil))
                }.font(.system(size: 12))
                if style.validTint != nil {
                    AavaColorWheel(title: "Tile tint", hex: Binding(get: { style.validTint ?? automatic }, set: { var value = style; value.tint = $0; store.tileStyle(id, value) })).frame(maxWidth: 300)
                } else {
                    Text("A soft gradient from this site’s favicon. Monochrome or missing icons use Aava’s periwinkle.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
                }
            } else {
                Text("Compact tiles show the favicon. Choose two columns to add a name and color.").font(.system(size: 12)).foregroundStyle(AavaSurfaceColors.secondary)
            }
        }.padding(.vertical, 4)
    }
}
