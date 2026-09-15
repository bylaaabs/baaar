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

/// Where the chevron points. It points where hidden items go: sideways into the menu bar, down into a panel.
enum ChevronDirection: Sendable {
    case left, right, down, up
}

/// The look of the chevron status item.
enum ChevronStyle: String, CaseIterable, Sendable {
    case chevron
    case arrow
    case triangle
    case circle
    case dots

    var title: String {
        switch self {
        case .chevron: "Chevron"
        case .arrow: "Arrow"
        case .triangle: "Triangle"
        case .circle: "Circle"
        case .dots: "Dots"
        }
    }

    /// SF Symbol for a direction. Dots don't point anywhere, so they fill in while open instead.
    func symbolName(_ direction: ChevronDirection) -> String {
        let way = switch direction {
        case .left: "left"
        case .right: "right"
        case .down: "down"
        case .up: "up"
        }
        return switch self {
        case .chevron: "chevron.\(way)"
        case .arrow: "arrow.\(way)"
        case .triangle: "arrowtriangle.\(way).fill"
        case .circle: "chevron.\(way).circle"
        case .dots: direction == .left || direction == .down ? "ellipsis" : "ellipsis.circle.fill"
        }
    }
}

/// Apple's menu bar items that MenuBarAgent lets baaar keep or hide individually.
///
/// The raw values are MenuBarClientCore's `MBSystemItemIdentifier`, verified on macOS 27
/// by withholding each one from the restriction and watching which item disappears.
enum SystemItem: Int, CaseIterable, Sendable {
    case battery = 0
    case bluetooth = 1
    case clock = 2
    case displays = 3
    case keyboard = 4
    case sound = 5
    case wifi = 6
    case screenMirroring = 7
    case controlCenter = 8

    /// The key used in place of a bundle identifier wherever apps and system items mix.
    var key: String {
        "system.\(self)"
    }

    init?(key: String) {
        guard let item = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = item
    }

    var symbolName: String {
        switch self {
        case .battery: "battery.75percent"
        case .bluetooth: "wave.3.right"
        case .clock: "clock"
        case .displays: "sun.max"
        case .keyboard: "light.max"
        case .sound: "speaker.wave.2.fill"
        case .wifi: "wifi"
        case .screenMirroring: "rectangle.on.rectangle"
        case .controlCenter: "switch.2"
        }
    }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .clock: "Clock"
        case .displays: "Displays"
        case .keyboard: "Keyboard Brightness"
        case .sound: "Sound"
        case .wifi: "Wi-Fi"
        case .screenMirroring: "Screen Mirroring"
        case .controlCenter: "Control Center"
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

    static var chevronStyle: ChevronStyle {
        get { defaults.string(forKey: "chevronStyle").flatMap(ChevronStyle.init(rawValue:)) ?? .chevron }
        set { defaults.set(newValue.rawValue, forKey: "chevronStyle") }
    }

    /// The section apps get the first time baaar sees them.
    static var newAppSection: MenuBarSection {
        get { defaults.string(forKey: "newAppSection").flatMap(MenuBarSection.init(rawValue:)) ?? .visible }
        set { defaults.set(newValue.rawValue, forKey: "newAppSection") }
    }

    /// Every app or system item key baaar has already placed, so new ones can go to `newAppSection`.
    static var knownKeys: Set<String> {
        get { Set(defaults.stringArray(forKey: "knownKeys") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "knownKeys") }
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

    /// The section of every app (bundle identifier) and system item (`SystemItem.key`) baaar has placed.
    static var sections: [String: MenuBarSection] {
        get {
            let stored = defaults.dictionary(forKey: Key.sections) as? [String: String] ?? [:]
            return stored.compactMapValues(MenuBarSection.init(rawValue:))
        }
        set {
            defaults.set(newValue.mapValues(\.rawValue), forKey: Key.sections)
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
