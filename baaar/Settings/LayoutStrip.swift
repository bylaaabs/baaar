import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One section of the layout editor: a dark menu-bar-like strip of chips, left to right, that
/// takes drops and shows a cyan caret where the dragged item would land.
struct LayoutStrip: View {
    let section: MenuBarSection
    let items: [AppModel.LayoutItem]
    /// Every strip's items, to find a dragged item that comes from another strip.
    let allItems: [AppModel.LayoutItem]
    let drag: LayoutDragSession
    let onDragStart: (String) -> Void
    let onPlace: (String, Int) -> Void
    let menu: (AppModel.LayoutItem) -> [BrandMenu.Item]

    static let spacing: CGFloat = 4
    private static let height: CGFloat = 44
    private static let caretHeight: CGFloat = 22

    /// Chip frames in the strip content's coordinate space, where drop locations are reported.
    @State private var frames: [String: CGRect] = [:]
    @State private var target: StripDropTarget?
    @State private var viewportWidth: CGFloat = 0

    private var coordinateSpaceName: String { "layout-strip-\(section.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.settingsLabel)
                    .font(.brandBody)
                    .foregroundStyle(BrandColors.on)
                Text(subtitle)
                    .font(.brandCaption)
                    .foregroundStyle(BrandColors.onSecondary)
                Spacer(minLength: 0)
                Text("\(items.count)")
                    .font(.brandBadge)
                    .foregroundStyle(BrandColors.onTertiary)
                    .monospacedDigit()
            }

            strip
        }
    }

    private var subtitle: String {
        switch section {
        case .visible: "always in the menu bar."
        case .hidden: "shown when you click the chevron."
        case .alwaysHidden: "shown when you ⌥ or ⌃ click the chevron."
        }
    }

    /// `surfaceElevated` with a one-pixel `separatorSolid` ring at radius 9; cyan ring and wash while a drop would land here.
    private var strip: some View {
        let isTargeted = target?.isActive == true
        let spaceName = coordinateSpaceName
        return ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                if items.isEmpty {
                    Text("drop items here")
                        .font(.brandCaption)
                        .foregroundStyle(BrandColors.onTertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(items) { item in
                        LayoutChip(item: item, isDragged: item.id == drag.itemID, onDragStart: onDragStart, menu: menu)
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(spaceName))
                            } action: { frame in
                                frames[item.id] = frame
                            }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: viewportWidth, minHeight: Self.height, alignment: .trailing)
            .overlay(alignment: .topLeading) { caret }
            .coordinateSpace(.named(spaceName))
            .onDrop(
                of: [.plainText],
                delegate: StripDropDelegate(section: section, items: items, allItems: allItems, drag: drag, frames: frames, target: $target, onPlace: onPlace)
            )
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .frame(height: Self.height)
        .background(isTargeted ? BrandColors.accentWash : .clear, in: RoundedRectangle(cornerRadius: 9))
        .brandHairlineBorder(
            cornerRadius: 9,
            fill: BrandColors.surfaceElevated,
            ring: isTargeted ? BrandColors.accent : BrandColors.separatorSolid
        )
        .animation(.easeOut(duration: 0.14), value: isTargeted)
        .onChange(of: drag.itemID == nil) { _, ended in
            if ended { target = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.settingsLabel) section")
    }

    @ViewBuilder
    private var caret: some View {
        if let x = target?.caretX {
            Capsule()
                .fill(BrandColors.accent)
                .frame(width: 2, height: Self.caretHeight)
                .offset(x: x - 1, y: (Self.height - Self.caretHeight) / 2)
                .animation(.easeOut(duration: 0.12), value: x)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

// MARK: - Dropping

/// What a drag over a strip would do.
struct StripDropTarget: Equatable {
    /// Where the item would land among the strip's other items.
    var index: Int
    /// False when the drop would leave everything as it is.
    var isActive: Bool
    /// The caret's centre, or nil when the order can't change.
    var caretX: CGFloat?
}

private struct StripDropDelegate: DropDelegate {
    let section: MenuBarSection
    let items: [AppModel.LayoutItem]
    let allItems: [AppModel.LayoutItem]
    let drag: LayoutDragSession
    let frames: [String: CGRect]
    @Binding var target: StripDropTarget?
    let onPlace: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        resolve(at: info.location) != nil
    }

    func dropEntered(info: DropInfo) {
        update(resolve(at: info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let resolved = resolve(at: info.location)
        update(resolved)
        return DropProposal(operation: resolved == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        update(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let resolved = resolve(at: info.location)
        update(nil)
        guard let dragged, let resolved, resolved.isActive else { return false }
        onPlace(dragged.id, resolved.index)
        return true
    }

    private var dragged: AppModel.LayoutItem? {
        drag.itemID.flatMap { id in allItems.first { $0.id == id } }
    }

    private func update(_ new: StripDropTarget?) {
        if target != new { target = new }
    }

    /// Nil when this strip refuses the dragged item: nothing of baaar's is being dragged, or it can't be hidden.
    private func resolve(at location: CGPoint) -> StripDropTarget? {
        guard let dragged, dragged.allowedSections.contains(section) else { return nil }
        let neighbours = items.filter { $0.id != dragged.id }
        let current = items.firstIndex { $0.id == dragged.id }

        guard dragged.canReorder else {
            // It keeps its place: it can only change strips.
            return StripDropTarget(index: 0, isActive: current == nil, caretX: nil)
        }

        let index = neighbours.count { (frames[$0.id]?.midX ?? .infinity) < location.x }
        guard index != current else { return StripDropTarget(index: index, isActive: false, caretX: nil) }

        let half = LayoutStrip.spacing / 2
        let caretX: CGFloat? = if neighbours.isEmpty {
            nil
        } else if index == 0 {
            frames[neighbours[0].id].map { $0.minX - half }
        } else {
            frames[neighbours[index - 1].id].map { $0.maxX + half }
        }
        return StripDropTarget(index: index, isActive: true, caretX: caretX)
    }
}

// MARK: - Chip

private struct LayoutChip: View {
    let item: AppModel.LayoutItem
    let isDragged: Bool
    let onDragStart: (String) -> Void
    let menu: (AppModel.LayoutItem) -> [BrandMenu.Item]

    private static let maxImageHeight: CGFloat = 18

    @State private var isHovered = false

    var body: some View {
        glyph
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(isHovered && !isDragged ? BrandColors.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: 6))
            .opacity(isDragged ? 0.35 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isDragged)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
            .accessibilityActions {
                let entries = menu(item)
                ForEach(entries.indices, id: \.self) { index in
                    Button(entries[index].title, action: entries[index].action)
                }
            }
            .onDrag {
                onDragStart(item.id)
                return NSItemProvider(object: "baaar-layout-item:\(item.id)" as NSString)
            } preview: {
                glyph
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .brandHairlineBorder(cornerRadius: 7, fill: BrandColors.surfaceHigh)
                    .environment(\.colorScheme, .dark)
            }
            .brandContextMenu { menu(item) }
    }

    /// The name, plus why the item can't change strips when it can't.
    private var help: String {
        guard item.allowedSections.count == 1, let only = item.allowedSections.first else { return item.name }
        return only == .visible
            ? "\(item.name) - baaar's own items stay visible"
            : "\(item.name) - macos hides this while anything is hidden, and shows it again when nothing is"
    }

    @ViewBuilder
    private var glyph: some View {
        if let image = item.image {
            let size = Self.displaySize(of: image)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        } else if let icon = item.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.maxImageHeight, height: Self.maxImageHeight)
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BrandColors.on)
                .frame(width: Self.maxImageHeight, height: Self.maxImageHeight)
        }
    }

    /// Natural size in points, scaled down to fit the menu bar height.
    private static func displaySize(of image: NSImage) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxImageHeight, height: maxImageHeight) }
        guard size.height > maxImageHeight else { return size }
        let scale = maxImageHeight / size.height
        return CGSize(width: (size.width * scale).rounded(), height: maxImageHeight)
    }
}
