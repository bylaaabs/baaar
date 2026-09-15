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
        /// baaar's own items and Apple modules MenuBarAgent won't keep visible stay in the visible section.
        let canHide: Bool
        /// Needs the layout table: items without an entry keep their place.
        let canReorder: Bool

        static func == (lhs: LayoutItem, rhs: LayoutItem) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.section == rhs.section && lhs.image === rhs.image
                && lhs.canHide == rhs.canHide && lhs.canReorder == rhs.canReorder
        }
    }

    /// Every item in the menu bar, left to right, for the layout editor.
    private(set) var layoutItems: [LayoutItem] = []
    /// Whether baaar can read and write macOS 27's menu bar layout table, needed to reorder items.
    private(set) var hasLayoutAccess = MenuBarLayoutTable.hasAccess

    func layoutItems(in section: MenuBarSection) -> [LayoutItem] {
        layoutItems.filter { $0.section == section }
    }

    /// Places an item at `index` among the items of `section` (left to right), changing its app's section if needed.
    func place(_ id: String, in section: MenuBarSection, at index: Int) {
        guard let item = layoutItems.first(where: { $0.id == id }) else { return }
        guard item.canHide || section == .visible else { return }
        let neighbours = layoutItems(in: section).map(\.id).filter { $0 != id }
        controller?.place(id, sectionKey: item.sectionKey, in: section, at: min(max(index, 0), neighbours.count), neighbours: item.canReorder ? neighbours : [])
        Task {
            // MenuBarAgent re-sorts within a moment; read the result back.
            try? await Task.sleep(for: .milliseconds(400))
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
        layoutItems = await controller.layoutEntries().map { entry in
            let item = entry.item
            let isAppleModule = item.bundleIdentifier == MenuBarItem.menuBarAgent && item.systemItem == nil
            return LayoutItem(
                id: entry.id,
                name: item.isOwn ? (item.identifier == ControlItems.Identifier.chevron ? "baaar chevron" : "baaar") : item.displayName,
                section: item.sectionKey.map(Settings.section(forBundle:)) ?? .visible,
                sectionKey: item.sectionKey,
                image: controller.images.image(for: item),
                appIcon: item.appIcon,
                symbolName: Self.symbolName(for: item),
                canHide: item.sectionKey != nil && !item.isOwn && !isAppleModule,
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
