import AppKit
import SwiftUI

/// The layout editor: the three sections as bars, with items dragged between them.
@MainActor
final class LayoutEditorWindowController: NSObject, NSWindowDelegate {
    private let controller: MenuBarController
    private var window: NSWindow?
    private var model: LayoutEditorModel?

    init(controller: MenuBarController) {
        self.controller = controller
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let isDark = controller.controls.appItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let model = LayoutEditorModel(controller: controller, isDarkMenuBar: isDark)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "baaar Layout"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LayoutEditorView(model: model))
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
        self.model = model

        // Items can only be dragged while on screen, so the menu bar stays fully revealed while editing.
        controller.holdsEverythingRevealed = true
        Task {
            await controller.apply(.all)
            try? await Task.sleep(for: .milliseconds(900))
            await controller.recordLayout()
            await model.reload()
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
        controller.holdsEverythingRevealed = false
        Task { await controller.apply(.none) }
    }
}

@MainActor
@Observable
final class LayoutEditorModel {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        let image: NSImage?

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id
        }
    }

    let isDarkMenuBar: Bool
    private(set) var sections: [MenuBarSection: [Item]] = [:]
    private(set) var isLoading = true
    private(set) var movingItemID: String?
    private(set) var status: String?

    @ObservationIgnored private let controller: MenuBarController

    init(controller: MenuBarController, isDarkMenuBar: Bool) {
        self.controller = controller
        self.isDarkMenuBar = isDarkMenuBar
    }

    func reload() async {
        let snapshot = await ItemScanner.scan()
        var grouped: [MenuBarSection: [Item]] = [:]
        for item in snapshot.items where item.isManageable {
            let image = controller.images.image(for: item) ?? item.appIcon
            grouped[controller.section(of: item, in: snapshot), default: []].append(Item(id: item.id, name: item.displayName, image: image))
        }
        sections = grouped
        isLoading = false
    }

    func move(_ id: String, to destination: MenuBarSection) async {
        guard movingItemID == nil, sections[destination]?.contains(where: { $0.id == id }) != true else { return }
        movingItemID = id
        status = "Moving…"
        let moved = await controller.move(id, to: destination)
        status = moved ? nil : "Couldn't move that item. Make sure it fits in the menu bar and try again."
        await reload()
        movingItemID = nil
    }
}

struct LayoutEditorView: View {
    let model: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Drag icons between sections and baaar rearranges the menu bar for you.")
                .foregroundStyle(.secondary)
            ForEach([MenuBarSection.visible, .hidden, .alwaysHidden], id: \.self) { section in
                SectionBar(section: section, model: model)
            }
            HStack {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                    Text("Reading the menu bar…").foregroundStyle(.secondary)
                } else if let status = model.status {
                    Text(status).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reload") {
                    Task { await model.reload() }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360, alignment: .topLeading)
    }
}

private struct SectionBar: View {
    let section: MenuBarSection
    let model: LayoutEditorModel
    @State private var isTargeted = false

    private var subtitle: String {
        switch section {
        case .visible: "Always in the menu bar."
        case .hidden: "Shown when you click the ‹ chevron."
        case .alwaysHidden: "Shown when you ⌥-click the ‹ chevron."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.sections[section] ?? []) { item in
                        ItemChip(item: item, isMoving: model.movingItemID == item.id)
                            .draggable(item.id)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.isDarkMenuBar ? Color(white: 0.16) : Color(white: 0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
                    }
            }
            .environment(\.colorScheme, model.isDarkMenuBar ? .dark : .light)
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                Task { await model.move(id, to: section) }
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

private struct ItemChip: View {
    let item: LayoutEditorModel.Item
    let isMoving: Bool

    var body: some View {
        Group {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 64, maxHeight: 20)
            } else {
                Image(systemName: "questionmark.square.dashed")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
        .opacity(isMoving ? 0.4 : 1)
        .help(item.name)
    }
}
