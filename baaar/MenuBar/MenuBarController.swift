import AppKit

/// How much of the menu bar is showing.
enum Reveal: Int, Comparable {
    /// Hidden and always-hidden apps are concealed.
    case none
    /// Only always-hidden apps are concealed.
    case hidden
    /// Nothing is concealed.
    case all

    static func < (lhs: Reveal, rhs: Reveal) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Drives the real menu bar: which apps are concealed, opening hidden items, and picturing items.
///
/// Every change is a new restriction handed to MenuBarAgent, which applies it at
/// once, so there is no long-running state to get stuck in and nothing touches the cursor.
@MainActor
final class MenuBarController {
    let controls: ControlItems
    let images = ItemImageCache()
    private let restriction = VisibilityRestriction()

    private(set) var reveal: Reveal = .all
    /// Apps shown for a moment, e.g. the one whose item is being opened.
    private var temporarilyAllowed: Set<String> = []
    /// Apps concealed for a moment on top of the sections, to make room or to picture others.
    private var temporarilyConcealed: Set<String> = []

    private var activation: Task<Void, Never>?
    private var rehide: RehideMonitor?
    private var appObservers: [NSObjectProtocol] = []

    init(controls: ControlItems) {
        self.controls = controls
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            appObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A restriction allows the apps running when it was issued; newcomers need a fresh one.
                MainActor.assumeIsolated { self?.restriction.refreshAllowedApps() }
            })
        }
    }

    // MARK: - Sections

    func bundles(in sections: Set<MenuBarSection>) -> Set<String> {
        Set(Settings.sections.filter { sections.contains($0.value) }.keys)
    }

    func setSection(_ section: MenuBarSection, forBundle bundle: String) {
        Settings.setSection(section, forBundle: bundle)
        apply()
    }

    // MARK: - Reveal

    func setReveal(_ target: Reveal) {
        activation?.cancel()
        temporarilyAllowed = []
        temporarilyConcealed = []
        reveal = target
        apply()
        if target == .none {
            rehide = nil
        }
    }

    /// In "In the Menu Bar" mode: hide again after a click elsewhere or time away from the menu bar.
    func startRehideMonitor() {
        guard Settings.autoRehide else { return }
        rehide = RehideMonitor { [weak self] in
            self?.setReveal(.none)
        }
    }

    func displayModeChanged() {
        setReveal(.none)
    }

    private func apply() {
        var concealed: Set<String> = switch reveal {
        case .none: bundles(in: [.hidden, .alwaysHidden])
        case .hidden: bundles(in: [.alwaysHidden])
        case .all: []
        }
        concealed.formUnion(temporarilyConcealed)
        concealed.subtract(temporarilyAllowed)
        restriction.conceal(concealed)
        controls.setRevealed(reveal != .none, hasHiddenItems: !bundles(in: [.hidden, .alwaysHidden]).isEmpty)
    }

    // MARK: - Items

    /// Items of apps in the given sections that are running, in menu bar order.
    func items(in sections: Set<MenuBarSection>) async -> [MenuBarItem] {
        let bundles = bundles(in: sections)
        return await ItemScanner.scan().items.filter { item in
            item.isManageable && bundles.contains(item.bundleIdentifier ?? "")
        }
    }

    /// Every running app with items, for the layout editor.
    func appGroups() async -> [AppModel.AppGroup] {
        let snapshot = await ItemScanner.scan()
        var order: [String] = []
        var itemsByBundle: [String: [MenuBarItem]] = [:]
        for item in snapshot.items where item.isManageable {
            guard let bundle = item.bundleIdentifier else { continue }
            if itemsByBundle[bundle] == nil {
                order.append(bundle)
            }
            itemsByBundle[bundle, default: []].append(item)
        }
        return order.compactMap { bundle in
            guard let items = itemsByBundle[bundle], let first = items.first else { return nil }
            return AppModel.AppGroup(
                bundleIdentifier: bundle,
                name: first.displayName,
                section: Settings.section(forBundle: bundle),
                itemImages: items.compactMap { images.image(for: $0) },
                appIcon: first.appIcon
            )
        }
    }

    // MARK: - Opening an item

    /// Opens an item from the bar: shows its app for a moment so the item is drawn in the
    /// menu bar, presses it so its menu opens under it, and conceals it again once the menu closes.
    func activate(_ item: MenuBarItem) {
        activation?.cancel()
        activation = Task { [weak self] in
            await self?.performActivation(of: item)
        }
    }

    private func performActivation(of item: MenuBarItem) async {
        guard let bundle = item.bundleIdentifier else { return }
        let wasConcealed = restriction.concealedBundles.contains(bundle)
        var target = item
        if wasConcealed {
            temporarilyAllowed = [bundle]
            apply()
            if let shown = await waitUntilOnScreen(item.id) {
                target = shown
            } else if !Task.isCancelled {
                // No room next to the visible items: conceal the other apps for as long as the menu is open.
                let others = Set((await ItemScanner.scan()).items.compactMap(\.bundleIdentifier)).subtracting([bundle])
                temporarilyConcealed = others
                apply()
                target = await waitUntilOnScreen(item.id) ?? item
            }
        }
        guard !Task.isCancelled else { return }

        let baseline = WindowWatch.ids()
        AX.press(target.element, id: target.id)
        await waitWhilePopupOpen(of: target.pid, baseline: baseline)
        guard !Task.isCancelled else { return }
        temporarilyAllowed = []
        temporarilyConcealed = []
        apply()
    }

    /// Polls until the item is drawn in the menu bar, for up to two seconds.
    private func waitUntilOnScreen(_ id: String) async -> MenuBarItem? {
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return nil }
            let snapshot = await ItemScanner.scan()
            if let item = snapshot.item(id: id), snapshot.isOnScreen(item, concealed: restriction.concealedBundles) {
                // One more beat so the menu bar has finished sliding items into place.
                try? await Task.sleep(for: .milliseconds(120))
                return (await ItemScanner.scan()).item(id: id) ?? item
            }
        }
        return nil
    }

    /// Waits while the app shows a new menu or popover, for up to two minutes.
    private func waitWhilePopupOpen(of pid: pid_t, baseline: Set<CGWindowID>) async {
        // Give the menu a moment to appear; apps that open a window instead return right away.
        var sawPopup = false
        for _ in 0..<8 where !sawPopup {
            try? await Task.sleep(for: .milliseconds(100))
            sawPopup = !WindowWatch.newPopups(of: pid, since: baseline).isEmpty
        }
        guard sawPopup else {
            try? await Task.sleep(for: .milliseconds(400))
            return
        }
        var closedChecks = 0
        for _ in 0..<(120 * 4) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            closedChecks = WindowWatch.newPopups(of: pid, since: baseline).isEmpty ? closedChecks + 1 : 0
            if closedChecks >= 2 { return }
        }
    }

    // MARK: - Pictures

    /// Captures the items drawn right now.
    func captureVisibleItems() async {
        guard Permissions.hasScreenRecording else { return }
        let snapshot = await ItemScanner.scan()
        await images.capture(snapshot.items.filter { $0.isManageable && snapshot.isOnScreen($0, concealed: restriction.concealedBundles) })
    }

    /// Captures every item, hidden ones included, without touching the cursor: other apps are
    /// concealed for a moment so the hidden ones get drawn, a few apps at a time.
    func refreshImages() async {
        guard Permissions.hasScreenRecording, Permissions.hasAccessibility else { return }
        activation?.cancel()
        await captureVisibleItems()

        let snapshot = await ItemScanner.scan()
        let concealed = restriction.concealedBundles
        let missing = snapshot.items.filter { $0.isManageable && !snapshot.isOnScreen($0, concealed: concealed) }
        guard !missing.isEmpty else { return }
        let allBundles = Set(snapshot.items.filter(\.isManageable).compactMap(\.bundleIdentifier))
        let screenWidth = controls.screen?.frame.width ?? 1440

        for batch in Self.batches(of: missing, maxWidth: screenWidth * 0.3) {
            let shown = Set(batch.compactMap(\.bundleIdentifier))
            temporarilyAllowed = shown
            temporarilyConcealed = allBundles.subtracting(shown)
            apply()
            try? await Task.sleep(for: .milliseconds(700))
            let current = await ItemScanner.scan()
            let drawn = current.items.filter { shown.contains($0.bundleIdentifier ?? "") && current.isOnScreen($0, concealed: restriction.concealedBundles) }
            await images.capture(drawn)
        }
        temporarilyAllowed = []
        temporarilyConcealed = []
        apply()
    }

    /// Whether some running item has never been pictured.
    func hasItemsWithoutImages() async -> Bool {
        guard Permissions.hasScreenRecording else { return false }
        return await ItemScanner.scan().items.contains { $0.isManageable && images.image(for: $0) == nil }
    }

    /// Groups items by app into batches narrow enough to fit in the menu bar together.
    private static func batches(of items: [MenuBarItem], maxWidth: CGFloat) -> [[MenuBarItem]] {
        var byBundle: [String: [MenuBarItem]] = [:]
        for item in items {
            byBundle[item.bundleIdentifier ?? "", default: []].append(item)
        }
        var batches: [[MenuBarItem]] = []
        var current: [MenuBarItem] = []
        var width: CGFloat = 0
        for group in byBundle.values {
            let groupWidth = group.reduce(0) { $0 + ($1.frame?.width ?? 40) + 8 }
            if !current.isEmpty, width + groupWidth > maxWidth {
                batches.append(current)
                current = []
                width = 0
            }
            current += group
            width += groupWidth
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }
}

/// Ice-style smart rehide: a click on another app's window, or 15 seconds with the pointer away from the menu bar.
@MainActor
private final class RehideMonitor {
    private var monitor: Any?
    private var timer: Timer?
    private var awaySince: Date?
    private let menuBaseline = WindowWatch.ids()

    init(onRehide: @escaping @MainActor () -> Void) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard !Self.isInMenuBar(location), let window = WindowWatch.window(at: location) else { return }
                // Clicks inside menus and popovers keep the items out; clicks on app windows or the desktop don't.
                if window.layer <= 0 {
                    onRehide()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.isInMenuBar(NSEvent.mouseLocation) || !WindowWatch.newMenus(since: self.menuBaseline).isEmpty {
                    self.awaySince = nil
                } else if let awaySince = self.awaySince {
                    if Date().timeIntervalSince(awaySince) >= 15 {
                        onRehide()
                    }
                } else {
                    self.awaySince = Date()
                }
            }
        }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        timer?.invalidate()
    }

    private static func isInMenuBar(_ location: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        return location.y >= screen.frame.maxY - WindowWatch.menuBarHeight
    }
}
