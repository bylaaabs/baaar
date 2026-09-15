import AppKit

/// How much of the menu bar is on screen.
enum Reveal: Int, Comparable {
    /// Only the visible section.
    case none
    /// Visible and hidden sections.
    case hidden
    /// Everything, always-hidden section included.
    case all

    static func < (lhs: Reveal, rhs: Reveal) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Drives the real menu bar: collapsing and revealing sections, pressing hidden
/// items where they can be seen, and moving items between sections.
@MainActor
final class MenuBarController {
    let controls: ControlItems
    let images = ItemImageCache()

    /// Every divider starts at its natural width, so everything is on screen at launch.
    private(set) var reveal: Reveal = .all
    private(set) var isBusy = false
    /// Keeps everything revealed, e.g. while the layout editor is open.
    var holdsEverythingRevealed = false

    /// Time for the menu bar to finish animating items in or out before reading them.
    private let settleDelay = Duration.milliseconds(900)
    /// Whether a collapsed divider should push items into macOS's overflow; with nothing to its left it can't.
    private var expectsOverflow: [MenuBarSection: Bool] = [:]
    private var fitCheckTask: Task<Void, Never>?
    private var rehideTask: Task<Void, Never>?

    init(controls: ControlItems) {
        self.controls = controls
    }

    // MARK: - Reveal

    func apply(_ target: Reveal) async {
        guard !isBusy else { return }
        isBusy = true
        await transition(to: target)
        isBusy = false
    }

    private func transition(to target: Reveal) async {
        guard Permissions.hasAccessibility else { return }
        if target < reveal {
            // Read positions and pictures while the items that are about to hide are still on screen.
            await recordLayout()
        }
        switch target {
        case .all:
            controls.setNatural(.hidden)
            controls.setNatural(.alwaysHidden)
        case .hidden:
            controls.setNatural(.hidden)
            await collapse(.alwaysHidden)
        case .none:
            controls.setNatural(.alwaysHidden)
            await collapse(.hidden)
        }
        reveal = target
        scheduleFitChecks()
        if target == .none {
            rehideTask?.cancel()
        }
    }

    /// In "In the Menu Bar" mode, hides the sections again once the pointer has left the menu bar for a few seconds.
    func startRehideTimer() {
        rehideTask?.cancel()
        // Some apps keep windows at menu level all the time (Canopy's island); only new ones count as open menus.
        let existingMenus = Self.menuWindowIDs()
        rehideTask = Task { [weak self] in
            var idleSeconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.reveal != .none else { return }
                if self.isBusy || self.holdsEverythingRevealed || Self.isPointerInMenuBar() || !Self.menuWindowIDs().isSubset(of: existingMenus) {
                    idleSeconds = 0
                } else {
                    idleSeconds += 1
                }
                if idleSeconds >= 5 {
                    await self.apply(.none)
                    return
                }
            }
        }
    }

    // MARK: - Fitting dividers

    private enum Fit {
        case fits(CGRect)
        case tooWide
        case tooNarrow
    }

    /// Collapses a divider's section by stretching the divider to the left edge of the status area.
    ///
    /// Measured on macOS 27: a divider that exactly fits sends everything to its
    /// left into the overflow and stays on screen; a pixel wider and macOS
    /// overflows the divider too. The edge moves with the notch, the screen and,
    /// without a notch, the app menus, so baaar searches for it and remembers it.
    private func collapse(_ divider: MenuBarSection) async {
        guard let screen = controls.screen else { return }
        guard #available(macOS 27, *) else {
            // Up to macOS 26 an oversized item simply pushes its neighbours off screen.
            controls.setCollapsed(divider, width: 10_000)
            return
        }
        let identifier = controls.identifier(divider)
        if !controls.isNatural(divider) {
            controls.setNatural(divider)
        }
        try? await Task.sleep(for: .milliseconds(450))
        let before = await ItemScanner.scan()
        guard let natural = before.own(identifier)?.frame else {
            controls.setCollapsed(divider, width: (screen.frame.width * 0.2).rounded())
            return
        }
        let hasItemsLeft = before.overflowButtonFrame != nil
            || before.items.contains { $0.identifier != identifier && ($0.frame?.maxX ?? .infinity) <= natural.minX + 1 }
        expectsOverflow[divider] = hasItemsLeft

        let key = Self.screenKey(screen)
        let estimatedMinX = Settings.statusAreaMinX(screen: key) ?? Self.defaultStatusAreaMinX(screen)
        var low = natural.width
        var high = natural.maxX - screen.frame.minX
        var width = min(max(natural.maxX - estimatedMinX, low), high).rounded(.down)
        for _ in 0..<8 {
            controls.setCollapsed(divider, width: width)
            try? await Task.sleep(for: .milliseconds(450))
            switch fit(divider, in: await ItemScanner.scan(.controls)) {
            case .fits(let frame):
                Settings.setStatusAreaMinX(frame.minX, screen: key)
                return
            case .tooWide:
                high = width
            case .tooNarrow:
                low = width
            }
            guard high - low > 2 else { break }
            width = ((low + high) / 2).rounded(.down)
        }
        Log.write("collapse \(divider.rawValue): no exact fit, using \(low)")
        controls.setCollapsed(divider, width: low)
        expectsOverflow[divider] = false
    }

    private func fit(_ divider: MenuBarSection, in snapshot: MenuBarSnapshot) -> Fit {
        guard let frame = snapshot.own(controls.identifier(divider))?.frame else { return .tooWide }
        if let button = snapshot.overflowButtonFrame {
            // macOS parks its chevron where the first overflowed item was: right of our start means we overflowed.
            if button.minX > frame.minX + 1 { return .tooWide }
            // Flush against macOS's chevron (≈15 pt apart) means nothing is left between them.
            return frame.minX - button.maxX > Self.overflowButtonGap + 8 ? .tooNarrow : .fits(frame)
        }
        return expectsOverflow[divider] == true ? .tooNarrow : .fits(frame)
    }

    /// Re-fits the collapsed divider when what surrounds it changed width.
    func revalidateFit() async {
        guard reveal != .all, !isBusy else { return }
        let divider: MenuBarSection = reveal == .none ? .hidden : .alwaysHidden
        if case .fits = fit(divider, in: await ItemScanner.scan(.controls)) { return }
        isBusy = true
        await collapse(divider)
        isBusy = false
    }

    private func scheduleFitChecks() {
        fitCheckTask?.cancel()
        guard reveal != .all else { return }
        fitCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await self?.revalidateFit()
            }
        }
    }

    /// The spacing macOS 27 leaves between its overflow chevron and the next item.
    private static let overflowButtonGap: CGFloat = 15

    private static func screenKey(_ screen: NSScreen) -> String {
        "\(screen.localizedName)-\(Int(screen.frame.width))"
    }

    private static func defaultStatusAreaMinX(_ screen: NSScreen) -> CGFloat {
        if let notchSide = screen.auxiliaryTopRightArea {
            return notchSide.minX + 53
        }
        return screen.frame.minX + screen.frame.width * 0.52
    }

    // MARK: - Sections

    /// While items are on screen: remember where the dividers are, which section each item is in, and capture them.
    @discardableResult
    func recordLayout() async -> MenuBarSnapshot? {
        guard Permissions.hasAccessibility else { return nil }
        let snapshot = await ItemScanner.scan()
        if reveal >= .hidden, controls.isNatural(.hidden), let frame = snapshot.own(ControlItems.Identifier.hidden)?.frame {
            Settings.setDividerMinX(frame.minX, for: .hidden)
        }
        if reveal == .all, controls.isNatural(.alwaysHidden), let frame = snapshot.own(ControlItems.Identifier.alwaysHidden)?.frame {
            Settings.setDividerMinX(frame.minX, for: .alwaysHidden)
        }
        var sections: [String: MenuBarSection] = [:]
        for item in snapshot.items where item.isManageable && snapshot.isLaidOut(item) {
            sections[item.id] = section(of: item, in: snapshot)
        }
        Settings.setSections(sections)
        await images.capture(snapshot.items.filter { $0.isManageable && snapshot.isLaidOut($0) })
        return snapshot
    }

    func section(of item: MenuBarItem, in snapshot: MenuBarSnapshot) -> MenuBarSection {
        guard snapshot.isLaidOut(item), let frame = item.frame else {
            return Settings.section(forItem: item.id) ?? .hidden
        }
        guard let hiddenMinX = Settings.dividerMinX(.hidden), frame.midX < hiddenMinX else { return .visible }
        if let alwaysHiddenMinX = Settings.dividerMinX(.alwaysHidden), frame.midX < alwaysHiddenMinX {
            return .alwaysHidden
        }
        return .hidden
    }

    func items(in sections: Set<MenuBarSection>) async -> [MenuBarItem] {
        let snapshot = await ItemScanner.scan()
        return snapshot.items.filter { $0.isManageable && sections.contains(section(of: $0, in: snapshot)) }
    }

    /// The chevron's frame in AppKit screen coordinates; a collapsed divider is wide, but its chevron sits at its right edge.
    func chevronFrame() async -> CGRect? {
        let snapshot = await ItemScanner.scan(.controls)
        guard let frame = snapshot.own(ControlItems.Identifier.hidden)?.frame ?? snapshot.own(ControlItems.Identifier.app)?.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let width = min(frame.width, 28)
        return CGRect(x: frame.maxX - width, y: primaryHeight - frame.maxY, width: width, height: frame.height)
    }

    // MARK: - Pictures

    /// Captures every item, revealing the hidden sections and macOS's own overflow for a moment.
    func refreshImages() async {
        guard !isBusy else { return }
        isBusy = true
        let previous = reveal
        if previous != .all {
            await transition(to: .all)
            try? await Task.sleep(for: settleDelay)
        }
        await captureIncludingOverflow()
        if previous != .all {
            await transition(to: previous)
        }
        isBusy = false
    }

    /// Whether some item has never been pictured, so a launch should capture everything.
    func hasItemsWithoutImages() async -> Bool {
        guard Permissions.hasScreenRecording else { return false }
        return await ItemScanner.scan().items.contains { $0.isManageable && images.image(for: $0) == nil }
    }

    /// On a notched display items that don't fit sit behind the native `«` chevron and are
    /// never drawn. Expanding it lays them out left of the notch for a moment.
    func captureIncludingOverflow() async {
        guard let snapshot = await recordLayout(), let chevron = snapshot.overflowButtonFrame else { return }
        let collapsed = Set(snapshot.items.filter { $0.isManageable && !snapshot.isLaidOut($0) }.map(\.id))
        guard !collapsed.isEmpty else { return }
        SyntheticInput.click(at: CGPoint(x: chevron.midX, y: chevron.midY))
        try? await Task.sleep(for: settleDelay)
        let expanded = await ItemScanner.scan()
        await images.capture(expanded.items.filter { collapsed.contains($0.id) && expanded.isLaidOut($0) })
        await collapseOverflow(expanded)
    }

    private func collapseOverflow(_ snapshot: MenuBarSnapshot? = nil) async {
        var current = snapshot
        if current == nil {
            current = await ItemScanner.scan(.controls)
        }
        guard let button = current?.overflowButtonFrame else { return }
        SyntheticInput.click(at: CGPoint(x: button.midX, y: button.midY))
        try? await Task.sleep(for: settleDelay)
    }

    // MARK: - Pressing

    /// Opens a hidden item: shows it in the menu bar, presses it so its menu appears
    /// under it, and hides it again once the menu or popover closes.
    func activate(_ id: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let previous = reveal
        var snapshot = await ItemScanner.scan()
        guard let initial = snapshot.item(id: id) else { return }
        let needed: Reveal = switch section(of: initial, in: snapshot) {
        case .alwaysHidden: .all
        case .hidden: max(previous, .hidden)
        case .visible: previous
        }
        if needed > previous {
            await transition(to: needed)
            try? await Task.sleep(for: settleDelay)
            snapshot = await ItemScanner.scan()
        }
        var expandedOverflow = false
        if let item = snapshot.item(id: id), !snapshot.isLaidOut(item), let chevron = snapshot.overflowButtonFrame {
            SyntheticInput.click(at: CGPoint(x: chevron.midX, y: chevron.midY))
            expandedOverflow = true
            try? await Task.sleep(for: settleDelay)
            snapshot = await ItemScanner.scan()
        }

        if let target = snapshot.item(id: id) {
            let existingWindows = Self.onScreenWindowIDs()
            let result = await AX.press(target.element)
            if result != .success, result != .cannotComplete {
                Log.write("press \(id) failed with AXError \(result.rawValue)")
            }
            await Self.waitForPopups(of: target.pid, excluding: existingWindows)
        }

        if expandedOverflow {
            await collapseOverflow()
        }
        if needed > previous {
            await transition(to: previous)
        }
    }

    /// Waits while the app shows a menu or popover that wasn't on screen before the press.
    private static func waitForPopups(of pid: pid_t, excluding existing: Set<CGWindowID>) async {
        try? await Task.sleep(for: .milliseconds(350))
        var quietChecks = 0
        for _ in 0..<(10 * 60 * 4) {
            if hasNewPopup(of: pid, excluding: existing) {
                quietChecks = 0
            } else {
                quietChecks += 1
                if quietChecks >= 2 { return }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func windowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        Set(windowList().compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }

    private static func hasNewPopup(of pid: pid_t, excluding existing: Set<CGWindowID>) -> Bool {
        windowList().contains { window in
            guard let id = window[kCGWindowNumber as String] as? CGWindowID, !existing.contains(id) else { return false }
            return window[kCGWindowOwnerPID as String] as? pid_t == pid && (window[kCGWindowLayer as String] as? Int ?? 0) > 0
        }
    }

    private static func menuWindowIDs() -> Set<CGWindowID> {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return Set(windowList().compactMap { window in
            (window[kCGWindowLayer as String] as? Int) == menuLevel ? window[kCGWindowNumber as String] as? CGWindowID : nil
        })
    }

    private static func isPointerInMenuBar() -> Bool {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        return location.y >= screen.visibleFrame.maxY
    }

    // MARK: - Moving

    /// Puts baaar's own items back in order — always-hidden divider, chevron, app icon —
    /// when a new divider was placed at its default spot or the user dragged one past another.
    func ensureControlOrder() async {
        guard !isBusy, reveal == .all, Permissions.hasAccessibility else { return }
        isBusy = true
        defer { isBusy = false }
        for _ in 0..<3 {
            let snapshot = await ItemScanner.scan()
            guard let app = snapshot.own(ControlItems.Identifier.app)?.frame,
                  let hidden = snapshot.own(ControlItems.Identifier.hidden)?.frame,
                  let alwaysHidden = snapshot.own(ControlItems.Identifier.alwaysHidden)?.frame else { return }
            if !Settings.didPlaceAlwaysHiddenDivider {
                // A new always-hidden section starts empty: its divider goes before every item on screen.
                Settings.didPlaceAlwaysHiddenDivider = true
                let leftmost = snapshot.items
                    .filter { $0.isManageable && snapshot.isLaidOut($0) }
                    .compactMap(\.frame)
                    .min { $0.minX < $1.minX }
                if let leftmost, leftmost.minX < alwaysHidden.minX {
                    Log.write("placing the always-hidden divider at the left end")
                    await SyntheticInput.commandDrag(from: CGPoint(x: alwaysHidden.midX, y: alwaysHidden.midY), to: CGPoint(x: leftmost.minX + 3, y: leftmost.midY))
                    try? await Task.sleep(for: settleDelay)
                    continue
                }
            }
            if alwaysHidden.minX > hidden.minX {
                Log.write("reordering the always-hidden divider left of the chevron")
                await SyntheticInput.commandDrag(from: CGPoint(x: alwaysHidden.midX, y: alwaysHidden.midY), to: CGPoint(x: hidden.minX + 3, y: hidden.midY))
            } else if app.minX < hidden.minX {
                Log.write("reordering the app icon right of the chevron")
                await SyntheticInput.commandDrag(from: CGPoint(x: app.midX, y: app.midY), to: CGPoint(x: hidden.maxX - 3, y: hidden.midY))
            } else {
                return
            }
            try? await Task.sleep(for: settleDelay)
        }
    }

    /// Moves an item to another section with the same ⌘-drag a person would do.
    @discardableResult
    func move(_ id: String, to destination: MenuBarSection) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }

        let previous = reveal
        if previous != .all {
            await transition(to: .all)
            try? await Task.sleep(for: settleDelay)
        }
        var snapshot = await ItemScanner.scan()
        var expandedOverflow = false
        if let item = snapshot.item(id: id), !snapshot.isLaidOut(item), let chevron = snapshot.overflowButtonFrame {
            SyntheticInput.click(at: CGPoint(x: chevron.midX, y: chevron.midY))
            expandedOverflow = true
            try? await Task.sleep(for: settleDelay)
            snapshot = await ItemScanner.scan()
        }

        var moved = false
        if let item = snapshot.item(id: id), snapshot.isLaidOut(item), let frame = item.frame,
           let hidden = snapshot.own(ControlItems.Identifier.hidden)?.frame,
           let alwaysHidden = snapshot.own(ControlItems.Identifier.alwaysHidden)?.frame {
            // Dropping on a divider's left half inserts before it, on its right half after it.
            let target = switch destination {
            case .visible: CGPoint(x: hidden.maxX - 3, y: hidden.midY)
            case .hidden: CGPoint(x: hidden.minX + 3, y: hidden.midY)
            case .alwaysHidden: CGPoint(x: alwaysHidden.minX + 3, y: alwaysHidden.midY)
            }
            await SyntheticInput.commandDrag(from: CGPoint(x: frame.midX, y: frame.midY), to: target)
            try? await Task.sleep(for: .milliseconds(700))
            Settings.setSections([id: destination])
            moved = true
        } else {
            Log.write("move \(id) to \(destination.rawValue): item or dividers not on screen")
        }

        if expandedOverflow {
            await collapseOverflow()
        }
        await recordLayout()
        if previous != .all, !holdsEverythingRevealed {
            await transition(to: previous)
        }
        return moved
    }
}
