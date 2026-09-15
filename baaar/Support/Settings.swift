import Foundation
import ServiceManagement

/// The three parts of the menu bar baaar manages, left to right: always hidden, hidden, visible.
enum MenuBarSection: String, CaseIterable, Sendable {
    case visible
    case hidden
    case alwaysHidden

    var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}

/// How hidden items are shown when the chevron is clicked.
enum DisplayMode: String, CaseIterable, Sendable {
    /// Reveal them in place, in the menu bar itself.
    case menuBar
    /// A row of icons in a panel under the chevron, like the Ice Bar.
    case bar
    /// A list with each icon and its app name.
    case list
    /// A square grid, like the Windows notification area overflow.
    case grid

    var title: String {
        switch self {
        case .menuBar: "In the Menu Bar"
        case .bar: "Horizontal Bar"
        case .list: "Vertical List"
        case .grid: "Grid"
        }
    }
}

@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let collapsed = "collapsed"
        static let didOnboard = "didOnboard"
        static let displayMode = "displayMode"
        static let sections = "itemSections"
        static let dividerMinX = "dividerMinX"
        static let statusAreaMinX = "statusAreaMinX"
    }

    /// Whether the hidden sections were collapsed when baaar last ran.
    static var collapsed: Bool {
        get { defaults.object(forKey: Key.collapsed) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.collapsed) }
    }

    static var didPlaceAlwaysHiddenDivider: Bool {
        get { defaults.bool(forKey: "didPlaceAlwaysHiddenDivider") }
        set { defaults.set(newValue, forKey: "didPlaceAlwaysHiddenDivider") }
    }

    static var didOnboard: Bool {
        get { defaults.bool(forKey: Key.didOnboard) }
        set { defaults.set(newValue, forKey: Key.didOnboard) }
    }

    static var displayMode: DisplayMode {
        get { defaults.string(forKey: Key.displayMode).flatMap(DisplayMode.init(rawValue:)) ?? .bar }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    /// The section each item was last seen in, for items whose frame can't tell right now.
    static func section(forItem id: String) -> MenuBarSection? {
        (defaults.dictionary(forKey: Key.sections)?[id] as? String).flatMap(MenuBarSection.init(rawValue:))
    }

    static func setSections(_ sections: [String: MenuBarSection]) {
        guard !sections.isEmpty else { return }
        var stored = defaults.dictionary(forKey: Key.sections) ?? [:]
        for (id, section) in sections {
            stored[id] = section.rawValue
        }
        defaults.set(stored, forKey: Key.sections)
    }

    /// Where a divider sat at its natural width the last time it was on screen, in AX coordinates.
    ///
    /// Hidden items keep reporting their last frame, so comparing against these
    /// positions tells which section they belong to.
    static func dividerMinX(_ divider: MenuBarSection) -> CGFloat? {
        defaults.dictionary(forKey: Key.dividerMinX)?[divider.rawValue] as? CGFloat
    }

    static func setDividerMinX(_ value: CGFloat, for divider: MenuBarSection) {
        var stored = defaults.dictionary(forKey: Key.dividerMinX) ?? [:]
        stored[divider.rawValue] = value
        defaults.set(stored, forKey: Key.dividerMinX)
    }

    /// The leftmost x a collapsed divider can start at on a given screen, learned by fitting.
    static func statusAreaMinX(screen key: String) -> CGFloat? {
        defaults.dictionary(forKey: Key.statusAreaMinX)?[key] as? CGFloat
    }

    static func setStatusAreaMinX(_ value: CGFloat, screen key: String) {
        var stored = defaults.dictionary(forKey: Key.statusAreaMinX) ?? [:]
        stored[key] = value
        defaults.set(stored, forKey: Key.statusAreaMinX)
    }

    static var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.write("launch at login change failed: \(error)")
            }
        }
    }
}
