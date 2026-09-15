import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controls: ControlItems!
    private let bar = BarController()
    private let images = ItemImageCache()
    private var isBusy = false

    /// Time for the menu bar to finish animating items back in before capturing them.
    private let revealSettleDelay = Duration.milliseconds(900)

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
            // Items start out visible: let apps publish theirs, picture them, then hide.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
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
        try? await Task.sleep(for: revealSettleDelay)
        await recordVisibleLayout()
    }

    /// Shows the hidden section just long enough to picture its items again.
    private func refreshImages() async {
        guard controls.visibility == .hidden, !isBusy else {
            await recordVisibleLayout()
            return
        }
        isBusy = true
        controls.setVisibility(.shown)
        try? await Task.sleep(for: revealSettleDelay)
        await recordVisibleLayout()
        controls.setVisibility(.hidden)
        isBusy = false
    }

    /// While items are on screen: remember where the divider is and capture every visible item.
    private func recordVisibleLayout() async {
        guard Permissions.hasAccessibility else { return }
        let snapshot = await ItemScanner.scan()
        if let divider = ownDivider(in: snapshot), let frame = divider.frame {
            Settings.dividerMinX = frame.minX
        }
        let overflowEdge = snapshot.overflowButtonFrame?.maxX ?? -.infinity
        let visible = snapshot.items.filter { item in
            guard item.isPressable, !item.isOwn, let frame = item.frame else { return false }
            return frame.minX >= overflowEdge
        }
        await images.capture(visible)
    }

    /// The toggle is the own item labelled "baaar"; the divider is the other one.
    private func ownDivider(in snapshot: MenuBarSnapshot) -> MenuBarItem? {
        snapshot.ownItems.first { $0.label != "baaar" }
    }

    // MARK: - Bar

    private func openBar() async {
        guard Permissions.hasAccessibility else {
            presentBar(entries: [], message: "baaar needs Accessibility access — right-click the icon")
            return
        }
        let snapshot = await ItemScanner.scan()
        let dividerX = Settings.dividerMinX ?? .infinity
        let hidden = snapshot.items.filter { item in
            guard item.isPressable, !item.isOwn else { return false }
            return (item.frame?.midX ?? -.infinity) < dividerX
        }
        let entries = hidden.map { BarEntry(item: $0, image: images.image(for: $0)) }
        presentBar(entries: entries, message: entries.isEmpty ? "Nothing hidden — ⌘-drag icons to the left of ‹" : nil)
    }

    private func presentBar(entries: [BarEntry], message: String?) {
        bar.show(
            entries: entries,
            message: message,
            anchor: controls.toggle.button?.window?.frame,
            screen: controls.toggleScreen,
            appearance: controls.toggle.button?.effectiveAppearance
        )
    }

    private func press(_ item: MenuBarItem) {
        bar.close()
        // macOS 27 opens a hidden item's menu at its last on-screen spot without revealing it.
        let element = item.element
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            let result = AX.perform(kAXPressAction, on: element.raw)
            if result != .success {
                await showSection()
            }
        }
    }

    // MARK: - Menu

    private func showMenu() {
        bar.close()
        let menu = NSMenu()
        let sectionTitle = controls.visibility == .shown ? "Hide Items" : "Show Hidden Items in Menu Bar"
        addItem(to: menu, sectionTitle, #selector(menuToggleSection), key: "")
        addItem(to: menu, "Refresh Icons", #selector(menuRefreshImages), key: "")
        menu.addItem(.separator())
        addItem(to: menu, "How to Hide Icons…", #selector(showHowTo), key: "")
        addItem(to: menu, "Launch at Login", #selector(menuToggleLaunchAtLogin), key: "").state = Settings.launchesAtLogin ? .on : .off
        if !Permissions.hasAccessibility {
            addItem(to: menu, "Grant Accessibility Access…", #selector(menuOpenAccessibility), key: "")
        }
        if !Permissions.hasScreenRecording {
            addItem(to: menu, "Show Real Icons (Screen Recording)…", #selector(menuRequestScreenRecording), key: "")
        }
        addItem(to: menu, "Write Diagnostics", #selector(menuDiagnostics), key: "")
        menu.addItem(.separator())
        addItem(to: menu, "Quit baaar", #selector(NSApplication.terminate(_:)), key: "q").target = NSApp

        guard let button = controls.toggle.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 6), in: button)
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String) -> NSMenuItem {
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

    #if DEBUG
    /// Lets scripts drive the app: `notifyutil` can't carry a payload, so the command is the name suffix.
    private func listenForDebugCommands() {
        let commands: [String: @MainActor @Sendable (AppDelegate) async -> Void] = [
            "hide": { await $0.hideSection() },
            "show": { await $0.showSection() },
            "refresh": { await $0.refreshImages() },
            "bar": { await $0.openBar() },
            "close": { $0.bar.close() },
        ]
        for (name, command) in commands {
            DistributedNotificationCenter.default().addObserver(forName: .init("com.aaangelmartin.baaar.debug.\(name)"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await command(self) }
                }
            }
        }
    }
    #endif

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
}
