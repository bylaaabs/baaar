import AppKit

/// baaar's two status items: the chevron, which hides and shows, and the app icon, which opens settings.
@MainActor
final class ControlItems {
    enum Identifier {
        static let app = "baaar.app"
        static let chevron = "baaar.chevron"
    }

    let appItem: NSStatusItem
    let chevronItem: NSStatusItem

    var onAppClick: ((NSEvent?) -> Void)?
    var onChevronClick: ((NSEvent?) -> Void)?

    init() {
        // Autosave names are kept from earlier builds so macOS keeps the spots the user ⌘-dragged them to.
        Self.seedPreferredPosition(1, for: "baaarToggle")
        Self.seedPreferredPosition(2, for: "baaarDivider")

        appItem = Self.makeItem(autosaveName: "baaarToggle", identifier: Identifier.app)
        chevronItem = Self.makeItem(autosaveName: "baaarDivider", identifier: Identifier.chevron)

        appItem.button?.image = Self.symbol("menubar.rectangle", description: "baaar settings")
        appItem.button?.target = self
        appItem.button?.action = #selector(appClicked)
        appItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        chevronItem.button?.target = self
        chevronItem.button?.action = #selector(chevronClicked)
        chevronItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        setRevealed(false, hasHiddenItems: true)
    }

    var screen: NSScreen? {
        chevronItem.button?.window?.screen ?? NSScreen.main
    }

    var menuBarAppearance: NSAppearance? {
        chevronItem.button?.effectiveAppearance
    }

    /// The chevron points at where the hidden items go: left to show them, right to tuck them away.
    func setRevealed(_ revealed: Bool, hasHiddenItems: Bool) {
        let description = revealed ? "Hide menu bar items" : "Show hidden menu bar items"
        chevronItem.button?.image = Self.symbol(revealed ? "chevron.right" : "chevron.left", description: description)
        chevronItem.button?.appearsDisabled = !hasHiddenItems && !revealed
    }

    @objc private func appClicked() {
        onAppClick?(NSApp.currentEvent)
    }

    @objc private func chevronClicked() {
        onChevronClick?(NSApp.currentEvent)
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

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}
