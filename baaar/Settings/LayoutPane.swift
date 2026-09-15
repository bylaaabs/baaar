import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct LayoutPane: View {
    let model: AppModel
    let reloader: ModelReloader

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if !model.canHideItems {
                BrandCallout(
                    systemImage: "exclamationmark.triangle",
                    tint: BrandColors.danger,
                    title: "hiding is not available on this Mac",
                    message: "this version of macOS does not let baaar hide menu bar items, so every section stays visible."
                )
            }

            if !model.hasAccessibility {
                BrandCallout(
                    systemImage: "hand.raised",
                    title: "accessibility access needed",
                    message: "baaar needs accessibility access to list and open menu bar items.",
                    actionTitle: "grant access",
                    action: model.requestAccessibility
                )
            }

            ForEach(MenuBarSection.allCases, id: \.self) { section in
                SectionBar(section: section, groups: model.groups(in: section)) { id in
                    move(id, to: section)
                } onMove: { id, target in
                    move(id, to: target)
                }
            }

            Text("every icon one tool puts in the menu bar moves together. Apple's items listed here can be hidden one by one; other Apple items, like focus or fast user switching, disappear while anything is hidden.")
                .font(.brandCaption)
                .foregroundStyle(BrandColors.onTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { reloader.reloadIfStale() }
    }

    /// Like `AppModel.move`, but a burst of drops shares one reload instead of re-reading the menu bar per drop.
    private func move(_ bundleIdentifier: String, to section: MenuBarSection) {
        model.controller?.setSection(section, forBundle: bundleIdentifier)
        reloader.request()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("drag items between sections")
                    .font(.brandHeadline)
                    .foregroundStyle(BrandColors.on)
                Text("right-click an item to move it without dragging.")
                    .font(.brandCaption)
                    .foregroundStyle(BrandColors.onSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            PillButton("refresh icons", kind: .secondary) {
                Task { await model.refreshIcons() }
            } leading: {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(BrandColors.accent)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BrandColors.onSecondary)
                }
            }
            .disabled(model.isRefreshing)
        }
    }
}

// MARK: - Section bar

private struct SectionBar: View {
    let section: MenuBarSection
    let groups: [AppModel.AppGroup]
    let onDrop: (String) -> Void
    let onMove: (String, MenuBarSection) -> Void

    @State private var isTargeted = false
    @State private var viewportWidth: CGFloat = 0

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
                Text("\(groups.count)")
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
        case .alwaysHidden: "shown when you ⌥-click the chevron."
        }
    }

    /// A menu bar strip: `surfaceElevated`, a one-pixel `separatorSolid` ring at radius 9. A drop
    /// target turns the ring cyan and washes the fill.
    private var strip: some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                if groups.isEmpty {
                    Text("drop items here")
                        .font(.brandCaption)
                        .foregroundStyle(BrandColors.onTertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(groups) { group in
                        AppGroupChip(group: group, onMove: onMove)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: viewportWidth, minHeight: 44, alignment: .trailing)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .frame(height: 44)
        .background(isTargeted ? BrandColors.accentWash : .clear, in: shape)
        .brandHairlineBorder(
            cornerRadius: 9,
            fill: BrandColors.surfaceElevated,
            ring: isTargeted ? BrandColors.accent : BrandColors.separatorSolid
        )
        .animation(.easeOut(duration: 0.14), value: isTargeted)
        .dropDestination(for: AppGroupDrag.self) { items, _ in
            let moved = items.filter { drag in
                groups.allSatisfy { $0.bundleIdentifier != drag.bundleIdentifier }
            }
            for drag in moved {
                onDrop(drag.bundleIdentifier)
            }
            return !items.isEmpty
        } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.settingsLabel) section")
    }
}

// MARK: - Chip

private struct AppGroupChip: View {
    let group: AppModel.AppGroup
    let onMove: (String, MenuBarSection) -> Void

    private static let maxImageHeight: CGFloat = 18

    @State private var isHovered = false

    var body: some View {
        content
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(isHovered ? BrandColors.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .help(group.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.name)
            .accessibilityActions {
                ForEach(MenuBarSection.allCases.filter { $0 != group.section }, id: \.self) { section in
                    Button("move to \(section.settingsLabel)") { onMove(group.bundleIdentifier, section) }
                }
            }
            .draggable(AppGroupDrag(bundleIdentifier: group.bundleIdentifier)) {
                content
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .brandHairlineBorder(cornerRadius: 7, fill: BrandColors.surfaceHigh)
                    .environment(\.colorScheme, .dark)
            }
            .brandContextMenu {
                MenuBarSection.allCases.filter { $0 != group.section }.map { section in
                    BrandMenu.Item("move to \(section.settingsLabel)", symbol: section.symbolName) {
                        onMove(group.bundleIdentifier, section)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if group.itemImages.isEmpty {
            if let icon = group.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            } else if group.isSystem, let item = SystemItem(key: group.bundleIdentifier) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrandColors.on)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(BrandColors.onSecondary)
            }
        } else {
            HStack(spacing: 2) {
                ForEach(group.itemImages.indices, id: \.self) { index in
                    let image = group.itemImages[index]
                    let size = Self.displaySize(of: image)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                }
            }
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

private extension MenuBarSection {
    var symbolName: String {
        switch self {
        case .visible: "eye"
        case .hidden: "eye.slash"
        case .alwaysHidden: "lock"
        }
    }
}

// MARK: - Drag payload

extension UTType {
    static let baaarAppGroup = UTType(exportedAs: "com.laaabs.baaar.app-group", conformingTo: .data)
}

/// What a dragged chip carries: just the owner (bundle or system item key) it stands for.
struct AppGroupDrag: Codable, Transferable {
    private static let stringPrefix = "baaar-app-group:"

    struct InvalidPayload: Error {}

    let bundleIdentifier: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .baaarAppGroup)
        // Fallback in case the undeclared custom type doesn't survive the pasteboard.
        ProxyRepresentation(exporting: { stringPrefix + $0.bundleIdentifier }, importing: { (string: String) in
            guard string.hasPrefix(stringPrefix) else { throw InvalidPayload() }
            return AppGroupDrag(bundleIdentifier: String(string.dropFirst(stringPrefix.count)))
        })
    }
}
