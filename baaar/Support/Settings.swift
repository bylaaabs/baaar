import Foundation
import ServiceManagement

/// The three sections of the menu bar. baaar assigns whole apps to them.
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
        static let sections = "appSections"
        static let displayMode = "displayMode"
        static let autoRehide = "autoRehide"
        static let didOnboard = "didOnboard"
        static let legacyItemSections = "itemSections"
    }

    static var displayMode: DisplayMode {
        get { defaults.string(forKey: Key.displayMode).flatMap(DisplayMode.init(rawValue:)) ?? .bar }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    static var autoRehide: Bool {
        get { defaults.object(forKey: Key.autoRehide) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoRehide) }
    }

    static var didOnboard: Bool {
        get { defaults.bool(forKey: Key.didOnboard) }
        set { defaults.set(newValue, forKey: Key.didOnboard) }
    }

    /// The section of every app the user placed; apps never placed are visible.
    static var sections: [String: MenuBarSection] {
        get {
            let stored = defaults.dictionary(forKey: Key.sections) as? [String: String] ?? [:]
            return stored.compactMapValues(MenuBarSection.init(rawValue:))
        }
        set {
            defaults.set(newValue.filter { $0.value != .visible }.mapValues(\.rawValue), forKey: Key.sections)
        }
    }

    static func section(forBundle bundle: String) -> MenuBarSection {
        sections[bundle] ?? .visible
    }

    static func setSection(_ section: MenuBarSection, forBundle bundle: String) {
        sections[bundle] = section
    }

    /// Carries over sections from the divider-based builds, which stored them per item ("bundle/label").
    static func migrateLegacySections() {
        guard defaults.object(forKey: Key.sections) == nil,
              let legacy = defaults.dictionary(forKey: Key.legacyItemSections) as? [String: String] else { return }
        var migrated: [String: MenuBarSection] = [:]
        for (itemID, raw) in legacy {
            guard let bundle = itemID.split(separator: "/").first.map(String.init),
                  let section = MenuBarSection(rawValue: raw), section != .visible else { continue }
            migrated[bundle] = section
        }
        sections = migrated
        for key in [Key.legacyItemSections, "dividerMinX", "statusAreaMinX", "didPlaceAlwaysHiddenDivider", "collapsed", "hidden", "barLayout"] {
            defaults.removeObject(forKey: key)
        }
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
