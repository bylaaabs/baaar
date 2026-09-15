import AppKit

/// The two status items baaar owns: the toggle (its icon) and the divider.
///
/// Everything the user ⌘-drags to the left of the divider belongs to the
/// hidden section. Hiding widens the divider until macOS can no longer fit it,
/// which sends the divider and every item to its left out of the menu bar.
@MainActor
final class ControlItems {
    enum Visibility {
        case shown
        case hidden
    }

    private enum AutosaveName {
        static let toggle = "baaarToggle"
        static let divider = "baaarDivider"
    }

    let toggle: NSStatusItem
    let divider: NSStatusItem
    private(set) var visibility: Visibility = .shown

    var onToggleClick: (() -> Void)?
    var onVisibilityChange: ((Visibility) -> Void)?

    init() {
        // Seed the first-launch order: toggle rightmost, divider just left of it.
        // Positions count points from the right edge; macOS keeps them after a ⌘-drag.
        Self.seedPreferredPosition(1, for: AutosaveName.toggle)
        Self.seedPreferredPosition(2, for: AutosaveName.divider)

        toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = AutosaveName.toggle
        divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = AutosaveName.divider

        if let button = toggle.button {
            button.image = Self.symbol("menubar.rectangle", description: "baaar")
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if let button = divider.button {
            button.image = Self.symbol("chevron.compact.left", description: "baaar divider")
            button.appearsDisabled = true
        }
    }

    var toggleScreen: NSScreen? {
        toggle.button?.window?.screen ?? NSScreen.main
    }

    func setVisibility(_ newValue: Visibility) {
        guard newValue != visibility else { return }
        visibility = newValue
        applyVisibility()
        onVisibilityChange?(newValue)
    }

    func toggleVisibility() {
        setVisibility(visibility == .shown ? .hidden : .shown)
    }

    /// Re-applies the current state, e.g. after the screen configuration changed.
    func applyVisibility() {
        switch visibility {
        case .shown:
            divider.length = NSStatusItem.variableLength
            divider.button?.image = Self.symbol("chevron.compact.left", description: "baaar divider")
        case .hidden:
            divider.button?.image = nil
            divider.length = HideLength.value(for: toggleScreen)
        }
    }

    @objc private func toggleClicked() {
        onToggleClick?()
    }

    private static func seedPreferredPosition(_ position: Double, for autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(position, forKey: key)
        }
    }

    private static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
