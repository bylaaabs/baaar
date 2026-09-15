import AppKit

/// The three status items baaar owns, right to left: the app icon, the hidden
/// section's chevron and the always-hidden divider.
///
/// Items ⌘-dragged left of the chevron are hidden; items left of the always-hidden
/// divider only show on request. A divider collapses its section by growing until
/// it spans to the left edge of the status area, which pushes everything to its
/// left into macOS's overflow while the divider itself stays on screen.
@MainActor
final class ControlItems {
    enum Identifier {
        static let app = "baaar.app"
        static let hidden = "baaar.divider.hidden"
        static let alwaysHidden = "baaar.divider.alwaysHidden"
    }

    let appItem: NSStatusItem
    let hiddenDivider: NSStatusItem
    let alwaysHiddenDivider: NSStatusItem

    var onAppClick: (() -> Void)?
    var onChevronClick: (() -> Void)?

    init() {
        // First-launch order, in points from the right edge; macOS keeps what the user ⌘-drags afterwards.
        Self.seedPreferredPosition(1, for: "baaarToggle")
        Self.seedPreferredPosition(2, for: "baaarDivider")
        Self.seedPreferredPosition(3, for: "baaarAlwaysHiddenDivider")

        appItem = Self.makeItem(autosaveName: "baaarToggle", identifier: Identifier.app)
        hiddenDivider = Self.makeItem(autosaveName: "baaarDivider", identifier: Identifier.hidden)
        alwaysHiddenDivider = Self.makeItem(autosaveName: "baaarAlwaysHiddenDivider", identifier: Identifier.alwaysHidden)

        appItem.button?.image = Self.symbol("menubar.rectangle", description: "baaar")
        for (item, action) in [(appItem, #selector(appClicked)), (hiddenDivider, #selector(chevronClicked))] {
            item.button?.target = self
            item.button?.action = action
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setNatural(.hidden)
        setNatural(.alwaysHidden)
    }

    var screen: NSScreen? {
        appItem.button?.window?.screen ?? NSScreen.main
    }

    func statusItem(_ divider: MenuBarSection) -> NSStatusItem {
        divider == .alwaysHidden ? alwaysHiddenDivider : hiddenDivider
    }

    func identifier(_ divider: MenuBarSection) -> String {
        divider == .alwaysHidden ? Identifier.alwaysHidden : Identifier.hidden
    }

    func isNatural(_ divider: MenuBarSection) -> Bool {
        statusItem(divider).length == NSStatusItem.variableLength
    }

    /// The divider at its own width, marking its section as shown.
    func setNatural(_ divider: MenuBarSection) {
        let item = statusItem(divider)
        item.length = NSStatusItem.variableLength
        item.button?.image = divider == .alwaysHidden
            ? Self.symbol("poweron", description: "Always hidden divider")
            : Self.symbol("chevron.right", description: "Hide menu bar items")
    }

    /// The divider stretched to `width`, marking its section as collapsed.
    func setCollapsed(_ divider: MenuBarSection, width: CGFloat) {
        let item = statusItem(divider)
        item.length = width
        // The chevron stays at the right edge, next to the visible items, so it reads as the boundary.
        item.button?.image = divider == .alwaysHidden ? nil : Self.trailingSymbol("chevron.left", width: width, description: "Show hidden menu bar items")
    }

    @objc private func appClicked() {
        onAppClick?()
    }

    @objc private func chevronClicked() {
        onChevronClick?()
    }

    private static func makeItem(autosaveName: String, identifier: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.button?.setAccessibilityIdentifier(identifier)
        return item
    }

    private static func seedPreferredPosition(_ position: Double, for autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(position, forKey: key)
        }
    }

    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(symbolConfiguration)
        image?.isTemplate = true
        return image
    }

    private static func trailingSymbol(_ name: String, width: CGFloat, description: String) -> NSImage? {
        guard let glyph = symbol(name, description: description) else { return nil }
        let size = NSSize(width: max(width - 8, glyph.size.width), height: max(glyph.size.height, 16))
        let image = NSImage(size: size, flipped: false) { rect in
            glyph.draw(in: NSRect(x: rect.maxX - glyph.size.width - 4, y: (rect.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
