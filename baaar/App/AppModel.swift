import AppKit
import Observation

/// Everything the settings window shows and edits. The UI talks only to this model.
@MainActor
@Observable
final class AppModel {
    /// One app, or one of Apple's system items, with menu bar items. Sections apply per app:
    /// macOS hides and shows whole bundles.
    struct AppGroup: Identifiable, Equatable {
        /// The app's bundle identifier, or `SystemItem.key` for Apple's system items.
        let bundleIdentifier: String
        let name: String
        let section: MenuBarSection
        /// Captured images of the app's items, left to right; empty when never captured.
        let itemImages: [NSImage]
        /// The app's own icon, shown when no item image exists.
        let appIcon: NSImage?
        /// Apple's system items (Clock, Wi-Fi, Control Center…) rather than an app.
        let isSystem: Bool

        var id: String { bundleIdentifier }

        static func == (lhs: AppGroup, rhs: AppGroup) -> Bool {
            lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.name == rhs.name && lhs.section == rhs.section
                && lhs.itemImages.elementsEqual(rhs.itemImages, by: ===) && lhs.appIcon === rhs.appIcon
        }
    }

    /// One item of the menu bar in the layout editor.
    struct LayoutItem: Identifiable, Equatable {
        /// The layout table id, or `ax:<item id>` when the table has no entry.
        let id: String
        let name: String
        let section: MenuBarSection
        /// The app bundle or system item key sections apply to; nil for items that can't be hidden.
        let sectionKey: String?
        let image: NSImage?
        let appIcon: NSImage?
        /// Shown when there's neither a captured image nor an app icon.
        let symbolName: String
        /// Sections the item may live in: baaar's own items stay visible; Apple modules outside the nine
        /// system items are hidden by macOS whenever anything is hidden, so they can't be placed.
        let allowedSections: Set<MenuBarSection>
        /// Needs the layout table: items without an entry keep their place.
        let canReorder: Bool

        static func == (lhs: LayoutItem, rhs: LayoutItem) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.section == rhs.section && lhs.image === rhs.image
                && lhs.allowedSections == rhs.allowedSections && lhs.canReorder == rhs.canReorder
        }
    }

    /// Every item in the menu bar, left to right, for the layout editor.
    private(set) var layoutItems: [LayoutItem] = []
    /// Whether baaar can read and write macOS 27's menu bar layout table, needed to reorder items.
    private(set) var hasLayoutAccess = MenuBarLayoutTable.hasAccess

    func layoutItems(in section: MenuBarSection) -> [LayoutItem] {
        layoutItems.filter { $0.section == section }
    }

    /// Applies an arrangement: `order` is every item left to right across the strips (always hidden,
    /// hidden, visible) and `sections` the new section of each app key that moved.
    func applyLayout(order: [String], sections: [String: MenuBarSection]) {
        controller?.applyLayout(order: order, sections: sections)
        Task {
            await reload()
        }
    }

    func requestLayoutAccess() {
        _ = MenuBarLayoutTable.requestAccess()
        hasLayoutAccess = MenuBarLayoutTable.hasAccess
        Task { await reload() }
    }

    /// Apps currently owning menu bar items, in menu bar order.
    private(set) var groups: [AppGroup] = []
    private(set) var isRefreshing = false
    private(set) var hasAccessibility = Permissions.hasAccessibility
    private(set) var hasScreenRecording = Permissions.hasScreenRecording
    /// False when this macOS lacks MenuBarAgent's visibility restriction, so nothing can be hidden.
    let canHideItems = VisibilityRestriction.isAvailable

    var displayMode: DisplayMode {
        didSet {
            guard displayMode != oldValue else { return }
            Settings.displayMode = displayMode
            controller?.displayModeChanged()
        }
    }

    var barColor: BarColor {
        didSet { Settings.barColor = barColor }
    }

    var chevronStyle: ChevronStyle {
        didSet {
            guard chevronStyle != oldValue else { return }
            Settings.chevronStyle = chevronStyle
            controller?.chevronStyleChanged()
        }
    }

    /// The section apps and system items get the first time baaar sees them.
    var newAppSection: MenuBarSection {
        didSet { Settings.newAppSection = newAppSection }
    }

    var autoRehide: Bool {
        didSet { Settings.autoRehide = autoRehide }
    }

    var launchesAtLogin: Bool {
        didSet {
            guard launchesAtLogin != Settings.launchesAtLogin else { return }
            Settings.launchesAtLogin = launchesAtLogin
        }
    }

    @ObservationIgnored weak var controller: MenuBarController?

    init() {
        displayMode = Settings.displayMode
        chevronStyle = Settings.chevronStyle
        barColor = Settings.barColor
        newAppSection = Settings.newAppSection
        autoRehide = Settings.autoRehide
        launchesAtLogin = Settings.launchesAtLogin
    }

    func groups(in section: MenuBarSection) -> [AppGroup] {
        groups.filter { $0.section == section }
    }

    /// Moves every item of an app to a section. Takes effect in the menu bar right away.
    func move(_ bundleIdentifier: String, to section: MenuBarSection) {
        controller?.setSection(section, forBundle: bundleIdentifier)
        Task { await reload() }
    }

    /// Re-reads the menu bar.
    func reload() async {
        refreshPermissions()
        guard let controller else { return }
        groups = await controller.appGroups()
        hasLayoutAccess = MenuBarLayoutTable.hasAccess
        let restricting = controller.isRestricting
        layoutItems = await controller.layoutEntries().map { entry in
            let item = entry.item
            let isAppleModule = item.bundleIdentifier == MenuBarItem.menuBarAgent && item.systemItem == nil
            let fixedSection: MenuBarSection? = item.isOwn ? .visible : isAppleModule ? (restricting ? .hidden : .visible) : nil
            return LayoutItem(
                id: entry.id,
                name: item.isOwn ? (item.identifier == ControlItems.Identifier.chevron ? "baaar chevron" : "baaar") : item.displayName,
                section: fixedSection ?? item.sectionKey.map(Settings.section(forBundle:)) ?? .visible,
                sectionKey: fixedSection == nil ? item.sectionKey : nil,
                // baaar's own items and Apple's have no useful app icon; the clock's picture would show a frozen time.
                image: item.isOwn || item.systemItem == .clock ? nil : controller.images.image(for: item),
                appIcon: item.isOwn || item.bundleIdentifier == MenuBarItem.menuBarAgent ? nil : item.appIcon,
                symbolName: Self.symbolName(for: item),
                allowedSections: fixedSection.map { [$0] } ?? Set(MenuBarSection.allCases),
                canReorder: hasLayoutAccess && entry.weight != nil
            )
        }
    }

    /// Captures fresh images of every item, hidden ones included, without touching the cursor.
    func refreshIcons() async {
        guard let controller, !isRefreshing else { return }
        isRefreshing = true
        await controller.refreshImages()
        isRefreshing = false
        await reload()
    }

    func refreshPermissions() {
        hasAccessibility = Permissions.hasAccessibility
        hasScreenRecording = Permissions.hasScreenRecording
        hasLayoutAccess = MenuBarLayoutTable.hasAccess
    }

    func requestAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    func requestScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    private static func symbolName(for item: MenuBarItem) -> String {
        if let systemItem = item.systemItem { return systemItem.symbolName }
        if item.isOwn {
            return item.identifier == ControlItems.Identifier.chevron ? Settings.chevronStyle.symbolName(Settings.displayMode == .menuBar ? .left : .down) : "menubar.rectangle"
        }
        let identifier = item.identifier?.lowercased() ?? ""
        switch true {
        case identifier.hasSuffix(".user"): return "person.crop.circle"
        case identifier.contains("focus"): return "moon.fill"
        case identifier.contains("nowplaying"): return "play.fill"
        case identifier.contains("audiovideo") || identifier.contains("privacy"): return "video.fill"
        default: return "app.dashed"
        }
    }
}
