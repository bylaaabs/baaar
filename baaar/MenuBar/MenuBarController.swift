import AppKit

/// How much of the menu bar is showing in place.
enum Reveal: Int, Comparable {
    /// Hidden and always-hidden items are concealed.
    case none
    /// Only always-hidden items are concealed.
    case hidden
    /// Nothing is concealed.
    case all

    static func < (lhs: Reveal, rhs: Reveal) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Drives the real menu bar: which items are concealed, opening hidden items, and picturing items.
///
/// Every change is a new restriction handed to MenuBarAgent, which applies it at
/// once, so nothing touches the cursor. Temporary changes (opening an item,
/// picturing hidden ones) belong to one task at a time: starting another, or any
/// user action, cancels it and puts the sections back.
@MainActor
final class MenuBarController {
    let controls: ControlItems
    let images = ItemImageCache()
    private let restriction = VisibilityRestriction()

    private(set) var reveal: Reveal = .none
    /// Whether a bar, list or grid is showing, so the chevron can point back up.
    var isPanelOpen = false {
        didSet { updateChevron() }
    }

    /// Keys shown or hidden on top of the sections by the current temporary task.
    private var temporarilyAllowed: Set<String> = []
    private var temporarilyConcealed: Set<String> = []
    private var temporaryTask: Task<Void, Never>?
    private var temporaryGeneration = 0

    private var rehide: RehideMonitor?
    private(set) var snapshot = MenuBarSnapshot(items: [])
    private var snapshotTask: Task<MenuBarSnapshot, Never>?
    private var captureFailures: [String: Date] = [:]
    /// Items as last seen, so the bar still lists Apple's items after MenuBarAgent drops concealed ones from AX.
    private var lastSeen: [String: MenuBarItem] = [:]
    /// Each item's position in the real left-to-right order, from the last layout read.
    private var layoutRank: [String: Int] = [:]

    private var clockMonitor: Any?

    init(controls: ControlItems) {
        self.controls = controls
        updateChevron()
        watchClockClicks()
        // Keep a recent picture of the menu bar so the bar opens instantly.
        Task { [weak self] in
            while !Task.isCancelled {
                // Reads the layout table too, so panels list items in the real order.
                _ = await self?.layoutEntries()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Sections

    func keys(in sections: Set<MenuBarSection>) -> Set<String> {
        Set(Settings.sections.filter { sections.contains($0.value) }.keys)
    }

    func section(of item: MenuBarItem) -> MenuBarSection {
        item.sectionKey.map(Settings.section(forBundle:)) ?? .visible
    }

    func setSection(_ section: MenuBarSection, forBundle key: String) {
        Settings.setSection(section, forBundle: key)
        Settings.knownKeys.insert(key)
        apply()
    }

    /// Places apps and system items seen for the first time in the section chosen for new apps.
    private func placeNewItems(in snapshot: MenuBarSnapshot) {
        let seen = Set(snapshot.items.filter(\.isManageable).compactMap(\.sectionKey))
        var known = Settings.knownKeys
        let isFirstRun = known.isEmpty
        let newcomers = seen.subtracting(known)
        guard !newcomers.isEmpty else { return }
        known.formUnion(newcomers)
        Settings.knownKeys = known
        // On the first run everything already in the menu bar stays where it is.
        guard !isFirstRun, Settings.newAppSection != .visible else { return }
        var sections = Settings.sections
        for key in newcomers where sections[key] == nil {
            sections[key] = Settings.newAppSection
        }
        Settings.sections = sections
        apply()
    }

    // MARK: - Reveal

    func setReveal(_ target: Reveal) {
        endTemporaryState()
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

    func chevronStyleChanged() {
        updateChevron()
    }

    private func apply() {
        var concealed: Set<String> = switch reveal {
        case .none: keys(in: [.hidden, .alwaysHidden])
        case .hidden: keys(in: [.alwaysHidden])
        case .all: []
        }
        concealed.formUnion(temporarilyConcealed)
        concealed.subtract(temporarilyAllowed)
        restriction.conceal(concealed)
        updateChevron()
    }

    private func updateChevron() {
        let isShowing = reveal != .none || isPanelOpen
        let direction: ChevronDirection = switch Settings.displayMode {
        case .menuBar: isShowing ? .right : .left
        case .bar, .list, .grid: isShowing ? .up : .down
        }
        controls.setChevron(style: Settings.chevronStyle, direction: direction, hasHiddenItems: !keys(in: [.hidden, .alwaysHidden]).isEmpty)
    }

    // MARK: - Temporary state

    /// Runs a temporary change to the restriction; the sections come back when it ends or is cancelled.
    private func runTemporary(_ work: @escaping @MainActor (_ isCurrent: @escaping @MainActor () -> Bool) async -> Void) {
        endTemporaryState()
        temporaryGeneration += 1
        let generation = temporaryGeneration
        temporaryTask = Task { [weak self] in
            await work { [weak self] in self?.temporaryGeneration == generation && !Task.isCancelled }
            guard let self, self.temporaryGeneration == generation else { return }
            self.temporarilyAllowed = []
            self.temporarilyConcealed = []
            self.temporaryTask = nil
            self.apply()
        }
    }

    private func endTemporaryState() {
        temporaryTask?.cancel()
        temporaryTask = nil
        temporaryGeneration += 1
        if !temporarilyAllowed.isEmpty || !temporarilyConcealed.isEmpty {
            temporarilyAllowed = []
            temporarilyConcealed = []
            apply()
        }
    }

    // MARK: - Items

    /// A fresh menu bar scan, shared by callers that ask at the same time.
    @discardableResult
    func refreshSnapshot() async -> MenuBarSnapshot {
        if let snapshotTask {
            return await snapshotTask.value
        }
        let task = Task { await ItemScanner.scan() }
        snapshotTask = task
        let fresh = await task.value
        snapshotTask = nil
        snapshot = fresh
        remember(fresh)
        placeNewItems(in: fresh)
        return fresh
    }

    private func remember(_ snapshot: MenuBarSnapshot) {
        let current = Set(snapshot.items.map(\.id))
        for item in snapshot.items where item.isPressable && !item.isOwn {
            lastSeen[item.id] = item
        }
        lastSeen = lastSeen.filter { id, item in
            guard !current.contains(id) else { return true }
            guard NSRunningApplication(processIdentifier: item.pid) != nil else { return false }
            // Keep items missing only because they're concealed. Apple modules outside the nine
            // system items vanish whenever any restriction is active.
            if let key = item.sectionKey {
                return restriction.concealedKeys.contains(key)
            }
            return !restriction.concealedKeys.isEmpty
        }
    }

    /// The scan's manageable items plus concealed ones it no longer reports, in menu bar order.
    private func manageableItems(in snapshot: MenuBarSnapshot) -> [MenuBarItem] {
        let present = Set(snapshot.items.map(\.id))
        let missing = lastSeen.values.filter { !present.contains($0.id) && $0.isManageable }
        return (snapshot.items.filter(\.isManageable) + missing).sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
    }

    /// Items in the given sections, in menu bar order, from the cached scan unless another is given.
    func items(in sections: Set<MenuBarSection>, from snapshot: MenuBarSnapshot? = nil) -> [MenuBarItem] {
        manageableItems(in: snapshot ?? self.snapshot)
            .filter { sections.contains(section(of: $0)) }
            .sorted { (layoutRank[$0.id] ?? .max, $0.frame?.minX ?? 0) < (layoutRank[$1.id] ?? .max, $1.frame?.minX ?? 0) }
    }

    /// Every app and system item in the menu bar, for the layout editor.
    func appGroups() async -> [AppModel.AppGroup] {
        let snapshot = await refreshSnapshot()
        var order: [String] = []
        var itemsByKey: [String: [MenuBarItem]] = [:]
        for item in manageableItems(in: snapshot) {
            guard let key = item.sectionKey else { continue }
            if itemsByKey[key] == nil {
                order.append(key)
            }
            itemsByKey[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let items = itemsByKey[key], let first = items.first else { return nil }
            return AppModel.AppGroup(
                bundleIdentifier: key,
                name: first.displayName,
                section: Settings.section(forBundle: key),
                itemImages: items.compactMap { images.image(for: $0) },
                appIcon: first.appIcon,
                isSystem: first.systemItem != nil
            )
        }
    }

    // MARK: - Layout

    /// One row of the layout editor: an item the menu bar shows, in its real order.
    struct LayoutEntry {
        /// The layout table's id (`status:<bundle>::<autosave>`, `module:<Name>`), or `ax:<item id>` without an entry.
        let id: String
        let weight: Double?
        let item: MenuBarItem
    }

    /// Every item in the menu bar, left to right, matched to its layout table entry when baaar can read the table.
    func layoutEntries() async -> [LayoutEntry] {
        let snapshot = await refreshSnapshot()
        let present = snapshot.items.filter(\.isPressable)
        let presentIDs = Set(present.map(\.id))
        let known = present + lastSeen.values.filter { !presentIDs.contains($0.id) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let positions = MenuBarLayoutTable.positions() ?? [:]

        var entries: [LayoutEntry] = []
        var used = Set<String>()
        var statusByBundle: [String: [(id: String, weight: Double)]] = [:]
        for (id, weight) in positions {
            if id.hasPrefix("status:"), let separator = id.range(of: "::") {
                let bundle = String(id[id.index(id.startIndex, offsetBy: 7)..<separator.lowerBound])
                // Entries of apps that aren't running (or of old installs) stay in the table; skip them.
                if running.contains(bundle) {
                    statusByBundle[bundle, default: []].append((id, weight))
                }
            } else if id.hasPrefix("module:") {
                let name = String(id.dropFirst(7))
                if let item = known.first(where: { !used.contains($0.id) && $0.bundleIdentifier == MenuBarItem.menuBarAgent && Self.module(name, matches: $0.identifier) }) {
                    used.insert(item.id)
                    entries.append(LayoutEntry(id: id, weight: weight, item: item))
                }
            }
        }
        for (bundle, tableEntries) in statusByBundle {
            let items = known.filter { $0.bundleIdentifier == bundle && !used.contains($0.id) }
            if bundle == Bundle.main.bundleIdentifier {
                // baaar's own items are named by autosave name.
                for entry in tableEntries {
                    let identifier = entry.id.hasSuffix("::baaarDivider") ? ControlItems.Identifier.chevron : entry.id.hasSuffix("::baaarToggle") ? ControlItems.Identifier.app : nil
                    if let item = items.first(where: { $0.identifier == identifier }) {
                        used.insert(item.id)
                        entries.append(LayoutEntry(id: entry.id, weight: entry.weight, item: item))
                    }
                }
                continue
            }
            // An app's entries and its items line up left to right.
            let sortedEntries = tableEntries.sorted { $0.weight > $1.weight }
            let sortedItems = items.sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
            for (entry, item) in zip(sortedEntries, sortedItems) {
                used.insert(item.id)
                entries.append(LayoutEntry(id: entry.id, weight: entry.weight, item: item))
            }
        }
        // Items the table doesn't list (or all of them, without access) fall back to their frames.
        for item in known where !used.contains(item.id) && (item.isManageable || item.isOwn || item.bundleIdentifier == MenuBarItem.menuBarAgent) {
            entries.append(LayoutEntry(id: "ax:\(item.id)", weight: nil, item: item))
        }
        let sorted = entries.sorted { lhs, rhs in
            switch (lhs.weight, rhs.weight) {
            case let (l?, r?) where l != r: l > r
            default: (lhs.item.frame?.minX ?? 0) < (rhs.item.frame?.minX ?? 0)
            }
        }
        layoutRank = Dictionary(sorted.enumerated().map { ($0.element.item.id, $0.offset) }) { first, _ in first }
        return sorted
    }

    /// Whether a layout table module name (`Clock`, `BentoBox-0`) names this MenuBarAgent item (`com.apple.menuextra.clock`).
    private static func module(_ name: String, matches identifier: String?) -> Bool {
        guard let identifier = identifier?.lowercased() else { return false }
        let base = name.split(separator: "-").first.map { String($0).lowercased() } ?? name.lowercased()
        let aliases: [String: [String]] = [
            "bentobox": ["controlcenter"],
            "userswitcher": ["user"],
            "focusmodes": ["focusmode", "focus"],
            "wifi": ["wifi"],
            "sound": ["sound", "volume"],
            "audiovideomodule": ["audiovideo", "avmodule", "privacy"],
            "keyboardbrightness": ["keyboard"],
            "display": ["display"],
            "screenmirroring": ["screenmirroring", "airplay"],
            "nowplaying": ["nowplaying"],
        ]
        let candidates = aliases[base] ?? [base]
        return candidates.contains { identifier.hasSuffix(".\($0)") || identifier.hasSuffix($0) }
    }

    /// Whether a restriction is hiding something right now, which also hides Apple modules outside the nine system items.
    var isRestricting: Bool {
        !restriction.concealedKeys.isEmpty
    }

    /// Applies an arrangement from the layout editor: section changes for apps, and the complete
    /// left-to-right order (always hidden, then hidden, then visible) written to the layout table
    /// as evenly spaced weights, so the table and the editor never disagree and sections stay contiguous.
    func applyLayout(order: [String], sections: [String: MenuBarSection]) {
        for (key, section) in sections where Settings.section(forBundle: key) != section {
            Settings.setSection(section, forBundle: key)
            Settings.knownKeys.insert(key)
        }
        apply()
        let tableIDs = order.filter { $0.hasPrefix("status:") || $0.hasPrefix("module:") }
        guard !tableIDs.isEmpty, MenuBarLayoutTable.positions() != nil else { return }
        var weights: [String: Double] = [:]
        for (offset, id) in tableIDs.enumerated() {
            weights[id] = Double((tableIDs.count - offset) * 32)
        }
        MenuBarLayoutTable.setPositions(weights)
    }

    // MARK: - Opening an item

    /// Opens an item from the bar: shows it for a moment so it is drawn in the menu bar,
    /// presses it so its menu opens under it, and conceals it again once the menu closes.
    func activate(_ item: MenuBarItem) {
        runTemporary { [weak self] isCurrent in
            await self?.performActivation(of: item, isCurrent: isCurrent)
        }
    }

    private func performActivation(of item: MenuBarItem, isCurrent: @escaping @MainActor () -> Bool) async {
        guard let key = item.sectionKey else { return }
        if item.systemItem == .clock {
            await openNotificationCenter(pressClock: true, isCurrent: isCurrent)
            return
        }
        var target = item
        if restriction.concealedKeys.contains(key) {
            temporarilyAllowed = [key]
            apply()
            if let shown = await waitUntilOnScreen(item.id, isCurrent: isCurrent) {
                target = shown
            } else if isCurrent() {
                // No room next to the visible items: conceal everything else while the menu is open.
                temporarilyConcealed = Set(snapshot.items.filter(\.isManageable).compactMap(\.sectionKey)).subtracting([key])
                apply()
                target = await waitUntilOnScreen(item.id, isCurrent: isCurrent) ?? item
            }
        }
        guard isCurrent() else { return }

        let baseline = WindowWatch.ids()
        let screenTop = Self.screenTop(for: target.frame)
        let pressState = PressState()
        let element = target.element
        let id = target.id
        Task.detached {
            await AX.press(element, id: id)
            await pressState.finish()
        }
        await waitWhileOpen(pid: target.pid, baseline: baseline, screenTop: screenTop, pressState: pressState, isCurrent: isCurrent)
    }

    /// Polls until the item is drawn in the menu bar, for up to two seconds.
    private func waitUntilOnScreen(_ id: String, isCurrent: @MainActor () -> Bool) async -> MenuBarItem? {
        var previousFrame: CGRect?
        for attempt in 0..<16 {
            try? await Task.sleep(for: .milliseconds(125))
            guard isCurrent() else { return nil }
            let snapshot = await ItemScanner.scan()
            guard let item = snapshot.item(id: id) else { continue }
            if snapshot.isOnScreen(item, concealed: restriction.concealedKeys) {
                // Settled once the frame holds still between two scans.
                if item.frame == previousFrame { return item }
                previousFrame = item.frame
            } else if attempt >= 3, snapshot.overflowButtonFrame != nil {
                // macOS put it in its own overflow: there's no room.
                return nil
            }
        }
        return nil
    }

    /// Waits while the pressed item's menu or popover is open, for up to two minutes.
    ///
    /// A menu keeps `AXPress` from returning until it closes; a popover returns at once
    /// but leaves a new window hanging from the menu bar. Either keeps the item out.
    private func waitWhileOpen(pid: pid_t, baseline: Set<CGWindowID>, screenTop: CGFloat, pressState: PressState, isCurrent: @MainActor () -> Bool) async {
        var sawPopup = false
        var quietChecks = 0
        for tick in 0..<(120 * 5) {
            try? await Task.sleep(for: .milliseconds(200))
            guard isCurrent() else { return }
            let pressReturned = await pressState.isFinished
            // Menus of helper processes belong to another pid, so any new window hanging from the bar counts.
            if !WindowWatch.newPopups(of: nil, since: baseline, screenTop: screenTop).isEmpty {
                sawPopup = true
                quietChecks = 0
                continue
            }
            if pressReturned {
                // Nothing opened within 1.5 s: it opened a window or did its thing silently.
                if !sawPopup, tick >= 7 { return }
                quietChecks += 1
                if sawPopup, quietChecks >= 2 { return }
            }
        }
    }

    // MARK: - Notification Center

    /// While any restriction is active MenuBarAgent won't open Notification Center from the clock,
    /// so a click on the clock lifts the restriction until Notification Center closes.
    private func watchClockClicks() {
        clockMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard let self, !self.restriction.concealedKeys.isEmpty, self.temporaryTask == nil,
                      let clock = self.snapshot.items.first(where: { $0.systemItem == .clock })?.frame,
                      let primaryHeight = NSScreen.screens.first?.frame.height,
                      clock.contains(CGPoint(x: location.x, y: primaryHeight - location.y)) else { return }
                self.runTemporary { [weak self] isCurrent in
                    await self?.openNotificationCenter(pressClock: false, isCurrent: isCurrent)
                }
            }
        }
    }

    private func openNotificationCenter(pressClock: Bool, isCurrent: @escaping @MainActor () -> Bool) async {
        temporarilyAllowed = restriction.concealedKeys
        apply()
        let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier
        func isOpen() -> Bool {
            guard let center else { return false }
            return WindowWatch.onScreen().contains { $0.pid == center && $0.layer > 0 && $0.bounds.width > 200 }
        }
        // The user's own click reaches MenuBarAgent once the restriction is gone; only press when it didn't open.
        try? await Task.sleep(for: .milliseconds(pressClock ? 150 : 450))
        guard isCurrent() else { return }
        if !isOpen() {
            if let clock = (await ItemScanner.scan()).items.first(where: { $0.systemItem == .clock }) {
                await AX.press(clock.element, id: clock.id)
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        for _ in 0..<(120 * 4) {
            guard isCurrent(), isOpen() else { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func screenTop(for frame: CGRect?) -> CGFloat {
        guard let frame, let primaryHeight = NSScreen.screens.first?.frame.height,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: primaryHeight - frame.midY)) })
        else { return 0 }
        return primaryHeight - screen.frame.maxY
    }

    // MARK: - Pictures

    /// Whether an item in the Hidden or Always Hidden section has never been pictured and hasn't failed recently.
    func hasHiddenItemsWithoutImages() async -> Bool {
        guard Permissions.hasScreenRecording else { return false }
        return !missingImages(in: await refreshSnapshot()).isEmpty
    }

    private func missingImages(in snapshot: MenuBarSnapshot) -> [MenuBarItem] {
        manageableItems(in: snapshot).filter { item in
            images.image(for: item) == nil && (captureFailures[item.id].map { Date().timeIntervalSince($0) > 3600 } ?? true)
        }
    }

    /// Pictures items without touching the cursor, a few at a time, each batch alone in the menu bar:
    /// every other item, Apple's included, is concealed and baaar's own items are blanked, so a stale
    /// frame can only land on empty space or on another item of the same batch, which the overlap check rejects.
    func refreshImages(onlyMissing: Bool = false) async {
        guard Permissions.hasScreenRecording, Permissions.hasAccessibility else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runTemporary { [weak self] isCurrent in
                await self?.performRefresh(onlyMissing: onlyMissing, isCurrent: isCurrent)
                self?.controls.setBlank(false)
                continuation.resume()
            }
        }
    }

    private func performRefresh(onlyMissing: Bool, isCurrent: @MainActor () -> Bool) async {
        let snapshot = await refreshSnapshot()
        let targets = onlyMissing ? missingImages(in: snapshot) : manageableItems(in: snapshot)
        guard !targets.isEmpty else { return }
        // A hidden menu bar (full screen, auto-hide) can't be pictured; wait for it rather than record failures.
        for _ in 0..<150 {
            if await ItemImageCache.isMenuBarOnScreen() { break }
            guard isCurrent() else { return }
            try? await Task.sleep(for: .seconds(2))
        }
        let everything = Set(manageableItems(in: snapshot).compactMap(\.sectionKey)).union(SystemItem.allCases.map(\.key))
        controls.setBlank(true)

        for batch in batches(of: targets) {
            guard isCurrent() else { return }
            let shown = Set(batch.compactMap(\.sectionKey))
            temporarilyAllowed = shown
            temporarilyConcealed = everything.subtracting(shown)
            apply()
            let drawn = await settledItems(batch.map(\.id), isCurrent: isCurrent)
            guard isCurrent() else { return }
            guard await images.capture(drawn) else { return }
            for item in batch where images.image(for: item) == nil {
                captureFailures[item.id] = Date()
            }
        }
    }

    /// Waits until the given items are drawn and their frames hold still between two scans, for up to two seconds.
    private func settledItems(_ ids: [String], isCurrent: @MainActor () -> Bool) async -> [MenuBarItem] {
        var previous: [String: CGRect] = [:]
        var settled: [MenuBarItem] = []
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(150))
            guard isCurrent() else { return [] }
            let snapshot = await ItemScanner.scan()
            let drawn = ids.compactMap(snapshot.item(id:)).filter { snapshot.isOnScreen($0, concealed: restriction.concealedKeys) }
            settled = drawn.filter { previous[$0.id] != nil && previous[$0.id] == $0.frame }
            if settled.count == ids.count { return settled }
            previous = Dictionary(uniqueKeysWithValues: drawn.compactMap { item in item.frame.map { (item.id, $0) } })
        }
        return settled
    }

    /// Groups items into batches narrow enough to fit next to the notch.
    private func batches(of items: [MenuBarItem]) -> [[MenuBarItem]] {
        let screen = controls.screen
        let available = max((screen?.auxiliaryTopRightArea?.width ?? (screen?.frame.width ?? 1440) / 2) - 220, 120)
        var byKey: [String: [MenuBarItem]] = [:]
        for item in items {
            byKey[item.sectionKey ?? "", default: []].append(item)
        }
        var batches: [[MenuBarItem]] = []
        var current: [MenuBarItem] = []
        var width: CGFloat = 0
        for group in byKey.values {
            let groupWidth = group.reduce(0) { $0 + ($1.frame?.width ?? 40) + 10 }
            if !current.isEmpty, width + groupWidth > available {
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

/// Whether a background `AXPress` has returned.
private actor PressState {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}

/// Ice-style smart rehide: a click outside the menu bar that isn't in a menu or popover,
/// or 15 seconds with the pointer away from the menu bar and nothing open.
@MainActor
private final class RehideMonitor {
    private var monitor: Any?
    private var timer: Timer?
    private var awaySince: Date?
    private var baseline = WindowWatch.ids()

    init(onRehide: @escaping @MainActor () -> Void) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard !Self.isInMenuBar(location) else { return }
                // Desktop clicks find no window; app windows sit at layer 0; menus and popovers above.
                if (WindowWatch.window(at: location)?.layer ?? 0) <= 0 {
                    onRehide()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.isInMenuBar(NSEvent.mouseLocation) || !WindowWatch.newPopups(of: nil, since: self.baseline, screenTop: 0).isEmpty {
                    self.awaySince = nil
                } else if let awaySince = self.awaySince {
                    if Date().timeIntervalSince(awaySince) >= 15 {
                        onRehide()
                    }
                } else {
                    self.awaySince = Date()
                    // Windows that stay up for good (a HUD, a pinned popover) shouldn't hold the items forever.
                    self.baseline = WindowWatch.ids()
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
