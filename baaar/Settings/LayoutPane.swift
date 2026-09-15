import AppKit
import SwiftUI

/// The menu bar layout editor: three strips in menu bar order. Drag to reorder, or between strips to hide.
struct LayoutPane: View {
    let model: AppModel
    let reloader: ModelReloader

    /// The layout as the last drop left it, shown until the model reads the menu bar back.
    @State private var draft: LayoutDraft?
    @State private var draftGeneration = 0
    @State private var drag = LayoutDragSession()

    private var items: [AppModel.LayoutItem] {
        draft?.apply(to: model.layoutItems) ?? model.layoutItems
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 24) {
            header

            if !model.canHideItems {
                BrandCallout(
                    systemImage: "exclamationmark.triangle",
                    tint: BrandColors.danger,
                    title: "hiding is not available on this mac",
                    message: "this version of macos doesn't let baaar hide menu bar items, so every item stays visible."
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

            if !model.hasLayoutAccess {
                BrandCallout(
                    systemImage: "arrow.left.arrow.right",
                    title: "reordering needs layout access",
                    message: "reordering needs access to the menu bar layout file. select com.apple.MenuBar.plist once and baaar can move items without touching your cursor.",
                    actionTitle: "grant access",
                    action: model.requestLayoutAccess
                )
            }

            ForEach(MenuBarSection.allCases, id: \.self) { section in
                LayoutStrip(
                    section: section,
                    items: items.filter { $0.section == section },
                    allItems: items,
                    drag: drag,
                    onDragStart: beginDrag,
                    onPlace: { id, index in place(id, in: section, at: index, items: items) },
                    menu: { item in menuItems(for: item, items: items) }
                )
            }

            Text("apple items other than wi-fi, bluetooth, battery, sound, displays, keyboard, screen mirroring, clock and control center can't be hidden: macos hides them itself while anything is hidden.")
                .font(.brandCaption)
                .foregroundStyle(BrandColors.onTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { reloader.reloadIfStale() }
        .onChange(of: model.layoutItems) {
            // The read-back of an earlier drop, or of this one once MenuBarAgent has re-sorted.
            if let draft, ContinuousClock.now - draft.createdAt >= .milliseconds(350) {
                self.draft = nil
            }
        }
        .task(id: draftGeneration) {
            // If the read-back never changes anything, stop pretending after a moment.
            let generation = draftGeneration
            try? await Task.sleep(for: .seconds(2.5))
            if draft?.generation == generation { draft = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("arrange your menu bar")
                    .font(.brandHeadline)
                    .foregroundStyle(BrandColors.on)
                Text("drag to reorder, or between strips to hide. every icon from the same tool moves together.")
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

    // MARK: - Moving

    private func beginDrag(_ id: String) {
        drag.itemID = id
        Task {
            // SwiftUI doesn't report a drag that ends outside a drop target; watch the mouse button instead.
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(250))
            if drag.itemID == id { drag.itemID = nil }
        }
    }

    /// Places an item at `index` among the other items of `section` as shown, left to right, and writes
    /// the whole arrangement: every strip in order, always hidden first, so the menu bar matches exactly.
    private func place(_ id: String, in section: MenuBarSection, at index: Int, items: [AppModel.LayoutItem]) {
        drag.itemID = nil
        guard let item = items.first(where: { $0.id == id }), item.allowedSections.contains(section) else { return }
        let neighbours = items.filter { $0.section == section && $0.id != id }
        let index = min(max(index, 0), neighbours.count)
        if item.section == section {
            let current = items.filter { $0.section == section }.firstIndex { $0.id == id }
            guard item.canReorder, current != index else { return }
        }

        draftGeneration += 1
        let draft = LayoutDraft(moving: item, to: section, at: index, in: items, generation: draftGeneration)
        self.draft = draft
        let arranged = draft.apply(to: items)
        let order = [MenuBarSection.alwaysHidden, .hidden, .visible].flatMap { strip in
            arranged.filter { $0.section == strip }.map(\.id)
        }
        var sections: [String: MenuBarSection] = [:]
        if let key = item.sectionKey, item.section != section {
            sections[key] = section
        }
        model.applyLayout(order: order, sections: sections)
    }

    private func menuItems(for item: AppModel.LayoutItem, items: [AppModel.LayoutItem]) -> [BrandMenu.Item] {
        var entries: [BrandMenu.Item] = []
        if item.allowedSections.count > 1 {
            let before = items.prefix { $0.id != item.id }
            for section in MenuBarSection.allCases where section != item.section {
                // Keep its place among the items already in that strip.
                let index = before.count { $0.section == section }
                entries.append(BrandMenu.Item("move to \(section.settingsLabel)", symbol: section.menuSymbol) {
                    place(item.id, in: section, at: index, items: items)
                })
            }
        }
        let strip = items.filter { $0.section == item.section }
        if item.canReorder, let position = strip.firstIndex(where: { $0.id == item.id }) {
            if position > 0 {
                entries.append(BrandMenu.Item("move to the start", symbol: "arrow.left.to.line") {
                    place(item.id, in: item.section, at: 0, items: items)
                })
            }
            if position < strip.count - 1 {
                entries.append(BrandMenu.Item("move to the end", symbol: "arrow.right.to.line") {
                    place(item.id, in: item.section, at: strip.count - 1, items: items)
                })
            }
        }
        return entries
    }
}

// MARK: - Drag

/// The item being dragged. A reference, so drop delegates see a drag the moment it starts,
/// before SwiftUI renders again.
@MainActor
@Observable
final class LayoutDragSession {
    var itemID: String?
}

// MARK: - Draft

/// An optimistic copy of the layout after a move: the new left-to-right order and section changes.
private struct LayoutDraft {
    let order: [String]
    let sections: [String: MenuBarSection]
    let generation: Int
    let createdAt = ContinuousClock.now

    init(moving item: AppModel.LayoutItem, to section: MenuBarSection, at index: Int, in items: [AppModel.LayoutItem], generation: Int) {
        var sections: [String: MenuBarSection] = [:]
        for other in items where other.id == item.id || (item.sectionKey != nil && other.sectionKey == item.sectionKey) {
            sections[other.id] = section
        }

        var order = items.map(\.id)
        let neighbours = items.filter { $0.section == section && $0.id != item.id }
        if item.canReorder, !neighbours.isEmpty {
            order.removeAll { $0 == item.id }
            if index < neighbours.count, let right = order.firstIndex(of: neighbours[index].id) {
                order.insert(item.id, at: right)
            } else if let last = neighbours.last, let left = order.firstIndex(of: last.id) {
                order.insert(item.id, at: left + 1)
            }
        }

        self.order = order
        self.sections = sections
        self.generation = generation
    }

    func apply(to items: [AppModel.LayoutItem]) -> [AppModel.LayoutItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }) { first, _ in first }
        let placed = Set(order)
        let ordered = order.compactMap { byID[$0] } + items.filter { !placed.contains($0.id) }
        return ordered.map { item in sections[item.id].map(item.moved(to:)) ?? item }
    }
}

private extension AppModel.LayoutItem {
    func moved(to section: MenuBarSection) -> Self {
        Self(
            id: id,
            name: name,
            section: section,
            sectionKey: sectionKey,
            image: image,
            appIcon: appIcon,
            symbolName: symbolName,
            allowedSections: allowedSections,
            canReorder: canReorder
        )
    }
}

private extension MenuBarSection {
    var menuSymbol: String {
        switch self {
        case .visible: "eye"
        case .hidden: "eye.slash"
        case .alwaysHidden: "eye.slash.circle"
        }
    }
}
