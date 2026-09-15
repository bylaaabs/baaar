import AppKit
import Observation

/// Everything the settings window shows and edits. The UI talks only to this model.
@MainActor
@Observable
final class AppModel {
    /// One app with menu bar items. Sections apply per app: macOS hides and shows whole bundles.
    struct AppGroup: Identifiable, Equatable {
        let bundleIdentifier: String
        let name: String
        let section: MenuBarSection
        /// Captured images of the app's items, left to right; empty when never captured.
        let itemImages: [NSImage]
        /// The app's own icon, shown when no item image exists.
        let appIcon: NSImage?

        var id: String { bundleIdentifier }

        static func == (lhs: AppGroup, rhs: AppGroup) -> Bool {
            lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.section == rhs.section && lhs.itemImages.count == rhs.itemImages.count
        }
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
            Settings.displayMode = displayMode
            controller?.displayModeChanged()
        }
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
}
