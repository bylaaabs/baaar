import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct LayoutPane: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !model.canHideItems {
                    Callout(
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "Hiding isn't supported on this Mac",
                        message: "This version of macOS doesn't let apps hide menu bar items, so every section stays visible."
                    )
                }

                if !model.hasAccessibility {
                    Callout(
                        systemImage: "hand.raised.fill",
                        tint: .accentColor,
                        title: "Accessibility access needed",
                        message: "baaar needs Accessibility access to list and open menu bar items.",
                        actionTitle: "Grant Access…",
                        action: model.requestAccessibility
                    )
                }

                ForEach(MenuBarSection.allCases, id: \.self) { section in
                    SectionBar(section: section, groups: model.groups(in: section)) { id in
                        model.move(id, to: section)
                    } onMove: { id, target in
                        model.move(id, to: target)
                    }
                }

                Text("Apple's own icons other than Wi-Fi, Bluetooth, Battery, Sound, Displays, Keyboard, Screen Mirroring, Clock and Control Center can't stay visible while items are hidden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drag apps between sections")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("baaar hides whole apps: every icon an app puts in the menu bar moves together.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.refreshIcons() }
            } label: {
                HStack(spacing: 6) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini)
                    }
                    Text("Refresh Icons")
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var isTargeted = false
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            strip
        }
    }

    private var subtitle: String {
        switch section {
        case .visible: "Always in the menu bar."
        case .hidden: "Shown when you click the ‹ chevron."
        case .alwaysHidden: "Shown when you ⌥-click the ‹ chevron."
        }
    }

    /// Captured items are drawn for the real menu bar, which follows the app's appearance.
    private var menuBarIsDark: Bool {
        _ = colorScheme // re-evaluate when the appearance changes
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var strip: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if groups.isEmpty {
                    Text("Drop apps here")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(groups) { group in
                        AppGroupChip(group: group, onMove: onMove)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: viewportWidth, minHeight: 52, alignment: .trailing)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .frame(height: 52)
        .background(Color(white: menuBarIsDark ? 0.15 : 0.9), in: shape)
        .overlay {
            shape.strokeBorder(
                isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                lineWidth: isTargeted ? 2 : 1
            )
        }
        .overlay {
            if isTargeted {
                shape.fill(.tint.opacity(0.08)).allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, menuBarIsDark ? .dark : .light)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
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
        .accessibilityLabel("\(section.title) section")
    }
}

// MARK: - Chip

private struct AppGroupChip: View {
    let group: AppModel.AppGroup
    let onMove: (String, MenuBarSection) -> Void

    private static let maxImageHeight: CGFloat = 18

    var body: some View {
        content
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 6, style: .continuous))
            .contentShape(.rect(cornerRadius: 6))
            .help(group.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.name)
            .draggable(AppGroupDrag(bundleIdentifier: group.bundleIdentifier)) {
                content
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .background(.regularMaterial, in: .rect(cornerRadius: 6, style: .continuous))
            }
            .contextMenu {
                ForEach(MenuBarSection.allCases, id: \.self) { section in
                    if section != group.section {
                        Button("Move to \(section.title)") {
                            onMove(group.bundleIdentifier, section)
                        }
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
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
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

// MARK: - Callout

private struct Callout: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(12)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Drag payload

extension UTType {
    static let baaarAppGroup = UTType(exportedAs: "com.aaangelmartin.baaar.app-group", conformingTo: .data)
}

/// What a dragged chip carries: just the app it stands for.
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
