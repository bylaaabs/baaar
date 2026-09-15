import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controls: ControlItems!
    private let bar = BarController()
    private let images = ItemImageCache()
    private var isBusy = false

    /// Time for the menu bar to finish animating items in or out before reading them.
    private let settleDelay = Duration.milliseconds(900)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controls = ControlItems()
        controls.onToggleClick = { [weak self] in self?.handleToggleClick() }
        bar.onSelect = { [weak self] item in self?.press(item) }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controls.applyVisibility() }
        }

        #if DEBUG
        listenForDebugCommands()
        #endif

        if CommandLine.arguments.contains("--diagnose") {
            Task {
                print(await Diagnostics.run(controls: controls).path)
                NSApp.terminate(nil)
            }
            return
        }

        if !Permissions.hasAccessibility {
            Permissions.requestAccessibility()
        }
        if !Settings.didOnboard {
            Settings.didOnboard = true
            showHowTo()
        } else if Settings.hidden {
            // Items start out visible: let apps publish theirs, picture what's missing, then hide.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await captureItems(includingOverflow: await hasItemsWithoutImages())
                await hideSection()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bar.close()
    }

    // MARK: - Toggle

    private func handleToggleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            Task { await toggleSection() }
        } else if controls.visibility == .shown {
            Task { await hideSection() }
        } else if bar.isVisible || Date().timeIntervalSince(bar.closedAt) < 0.3 {
            bar.close()
        } else {
            Task { await openBar() }
        }
    }

    private func toggleSection() async {
        if controls.visibility == .shown {
            await hideSection()
        } else {
            await showSection()
        }
    }

    private func hideSection() async {
        bar.close()
        guard controls.visibility == .shown, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await recordVisibleLayout()
        controls.setVisibility(.hidden)
        Settings.hidden = true
    }

    private func showSection() async {
        bar.close()
        guard controls.visibility == .hidden, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        controls.setVisibility(.shown)
        Settings.hidden = false
        try? await Task.sleep(for: settleDelay)
        await recordVisibleLayout()
    }

    /// Shows the hidden section, and macOS's own overflow, just long enough to picture every item.
    private func refreshImages() async {
        guard !isBusy else { return }
        let wasHidden = controls.visibility == .hidden
        isBusy = true
        if wasHidden {
            controls.setVisibility(.shown)
            try? await Task.sleep(for: settleDelay)
        }
        await captureItems(includingOverflow: true)
        if wasHidden {
            controls.setVisibility(.hidden)
        }
        isBusy = false
    }

    /// Captures the items on screen and, when asked, the ones in macOS's overflow.
    ///
    /// On a notched display items that don't fit sit behind the native `«` chevron
    /// and are never drawn. Expanding it lays them out left of the notch for a moment.
    private func captureItems(includingOverflow: Bool) async {
        guard let snapshot = await recordVisibleLayout() else { return }
        guard includingOverflow, let chevron = snapshot.overflowButtonFrame else { return }
        let collapsed = Set(snapshot.items.filter { isCandidate($0) && !isLaidOut($0, in: snapshot) }.map(\.id))
        guard !collapsed.isEmpty else { return }

        SyntheticClick.click(at: CGPoint(x: chevron.midX, y: chevron.midY))
        try? await Task.sleep(for: settleDelay)
        let expanded = await ItemScanner.scan()
        await images.capture(expanded.items.filter { collapsed.contains($0.id) && isLaidOut($0, in: expanded) })
        if let collapse = expanded.overflowButtonFrame {
            SyntheticClick.click(at: CGPoint(x: collapse.midX, y: collapse.midY))
            try? await Task.sleep(for: settleDelay)
        }
    }

    /// While items are on screen: remember where the divider is and capture every visible item.
    @discardableResult
    private func recordVisibleLayout() async -> MenuBarSnapshot? {
        guard Permissions.hasAccessibility else { return nil }
        let snapshot = await ItemScanner.scan()
        if let frame = ownDivider(in: snapshot)?.frame {
            Settings.dividerMinX = frame.minX
        }
        await images.capture(snapshot.items.filter { isCandidate($0) && isLaidOut($0, in: snapshot) })
        return snapshot
    }

    private func isCandidate(_ item: MenuBarItem) -> Bool {
        item.isPressable && !item.isOwn
    }

    /// Whether the item is actually drawn where AX says.
    ///
    /// Items collapsed into macOS's overflow keep stale frames that pile up on
    /// top of the chevron and of each other; capturing there would picture the chevron.
    private func isLaidOut(_ item: MenuBarItem, in snapshot: MenuBarSnapshot) -> Bool {
        // Neighbouring items legitimately overlap by a couple of points.
        let slack: CGFloat = 5
        guard let frame = item.frame?.insetBy(dx: slack, dy: 1) else { return false }
        if let chevron = snapshot.overflowButtonFrame, frame.intersects(chevron) { return false }
        return !snapshot.items.contains { other in
            guard other.id != item.id, other.isPressable, let otherFrame = other.frame else { return false }
            return frame.intersects(otherFrame.insetBy(dx: slack, dy: 1))
        }
    }

    private func hasItemsWithoutImages() async -> Bool {
        guard Permissions.hasScreenRecording else { return false }
        return await ItemScanner.scan().items.contains { $0.isPressable && !$0.isOwn && images.image(for: $0) == nil }
    }

    /// The toggle is the own item labelled "baaar"; the divider is the other one.
    private func ownDivider(in snapshot: MenuBarSnapshot) -> MenuBarItem? {
        snapshot.ownItems.first { $0.label != "baaar" }
    }

    /// The baaar icon's frame in AppKit screen coordinates, read from AX because
    /// macOS 27 stops updating status item window frames after a ⌘-drag.
    private func toggleFrame() async -> CGRect? {
        let own = await ItemScanner.scan(onlyOwn: true)
        guard let frame = own.ownItems.first(where: { $0.label == "baaar" })?.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            return controls.toggle.button?.window?.frame
        }
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    // MARK: - Bar

    private func openBar() async {
        let anchor = await toggleFrame()
        guard Permissions.hasAccessibility else {
            presentBar(entries: [], message: "baaar needs Accessibility access — right-click its icon", anchor: anchor)
            return
        }
        let snapshot = await ItemScanner.scan()
        let dividerX = Settings.dividerMinX ?? .infinity
        let hidden = snapshot.items.filter { item in
            guard item.isPressable, !item.isOwn else { return false }
            return (item.frame?.midX ?? -.infinity) < dividerX
        }
        let entries = hidden.map { BarEntry(item: $0, image: images.image(for: $0)) }
        presentBar(entries: entries, message: entries.isEmpty ? "Nothing hidden — ⌘-drag icons to the left of ‹" : nil, anchor: anchor)
    }

    private func presentBar(entries: [BarEntry], message: String?, anchor: CGRect?) {
        bar.show(
            entries: entries,
            message: message,
            layout: Settings.barLayout,
            anchor: anchor,
            screen: controls.toggleScreen,
            appearance: controls.toggle.button?.effectiveAppearance
        )
    }

    private func press(_ item: MenuBarItem) {
        bar.close()
        // macOS 27 opens a hidden item's menu at its last on-screen spot without revealing it.
        AX.pressInBackground(item.element, id: item.id)
    }

    // MARK: - Menu

    private func showMenu() {
        bar.close()
        let menu = NSMenu()
        let sectionTitle = controls.visibility == .shown ? "Hide Items" : "Show Hidden Items in Menu Bar"
        addItem(to: menu, sectionTitle, #selector(menuToggleSection))
        addItem(to: menu, "Refresh Icons", #selector(menuRefreshImages))
        menu.addItem(.separator())

        let layoutMenu = NSMenu()
        for (layout, title) in [(Settings.BarLayout.horizontal, "Horizontal Bar"), (.vertical, "Vertical List")] {
            let item = addItem(to: layoutMenu, title, #selector(menuSelectLayout(_:)))
            item.representedObject = layout.rawValue
            item.state = Settings.barLayout == layout ? .on : .off
        }
        menu.addItem(withTitle: "Bar Layout", action: nil, keyEquivalent: "").submenu = layoutMenu
        addItem(to: menu, "Launch at Login", #selector(menuToggleLaunchAtLogin)).state = Settings.launchesAtLogin ? .on : .off
        addItem(to: menu, "How to Hide Icons…", #selector(showHowTo))
        if !Permissions.hasAccessibility {
            addItem(to: menu, "Grant Accessibility Access…", #selector(menuOpenAccessibility))
        }
        if !Permissions.hasScreenRecording {
            addItem(to: menu, "Show Real Icons (Screen Recording)…", #selector(menuRequestScreenRecording))
        }
        addItem(to: menu, "Write Diagnostics", #selector(menuDiagnostics))
        menu.addItem(.separator())
        addItem(to: menu, "Quit baaar", #selector(NSApplication.terminate(_:)), key: "q").target = NSApp

        Task {
            guard let anchor = await toggleFrame() else { return }
            let menuBarBottom = controls.toggleScreen?.visibleFrame.maxY ?? anchor.minY
            // With no view the location is in screen coordinates and marks the menu's top-left corner.
            // It must sit below the menu bar, or AppKit clips the menu and adds a scroll arrow.
            let origin = NSPoint(x: anchor.midX - menu.size.width / 2, y: min(anchor.minY, menuBarBottom) - 2)
            menu.popUp(positioning: nil, at: origin, in: nil)
        }
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuToggleSection() {
        Task { await toggleSection() }
    }

    @objc private func menuRefreshImages() {
        Task { await refreshImages() }
    }

    @objc private func menuSelectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let layout = Settings.BarLayout(rawValue: raw) else { return }
        Settings.barLayout = layout
    }

    @objc private func menuToggleLaunchAtLogin() {
        Settings.launchesAtLogin.toggle()
    }

    @objc private func menuOpenAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc private func menuRequestScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    @objc private func menuDiagnostics() {
        Task {
            let url = await Diagnostics.run(controls: controls)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func showHowTo() {
        let alert = NSAlert()
        alert.messageText = "Hide icons with baaar"
        alert.informativeText = """
        Hold ⌘ and drag menu bar icons to the left of the ‹ divider. Everything left of it hides when you click the baaar icon.

        Click the baaar icon again to open the bar with your hidden icons, and click one to use it.
        ⌥-click shows them in the menu bar instead. Right-click for more options.
        """
        alert.addButton(withTitle: "Got It")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - Debug

    #if DEBUG
    /// Lets scripts drive the app through distributed notifications named `com.aaangelmartin.baaar.debug.<command>`.
    /// `press` takes the item's bundle identifier as the notification object.
    private func listenForDebugCommands() {
        let center = DistributedNotificationCenter.default()
        let commands: [String: @MainActor (AppDelegate, String?) async -> Void] = [
            "hide": { app, _ in await app.hideSection() },
            "show": { app, _ in await app.showSection() },
            "refresh": { app, _ in await app.refreshImages() },
            "bar": { app, _ in await app.openBar() },
            "close": { app, _ in app.bar.close() },
            "menu": { app, _ in app.showMenu() },
            "layout": { _, argument in Settings.barLayout = Settings.BarLayout(rawValue: argument ?? "") ?? .horizontal },
            "press": { app, bundleID in
                let item = await ItemScanner.scan().items.first { $0.bundleIdentifier == bundleID && $0.isPressable }
                if let item { app.press(item) }
            },
        ]
        for (name, command) in commands {
            center.addObserver(forName: .init("com.aaangelmartin.baaar.debug.\(name)"), object: nil, queue: .main) { [weak self] note in
                let argument = note.object as? String
                Task { @MainActor in
                    guard let self else { return }
                    await command(self, argument)
                }
            }
        }
    }
    #endif
}
