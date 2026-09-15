import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController!
    private var editor: LayoutEditorWindowController!
    private let bar = BarController()

    private var controls: ControlItems {
        controller.controls
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController(controls: ControlItems())
        editor = LayoutEditorWindowController(controller: controller)
        controls.onAppClick = { [weak self] in self?.appIconClicked() }
        controls.onChevronClick = { [weak self] in self?.chevronClicked(NSApp.currentEvent) }
        bar.onSelect = { [weak self] item in self?.activate(item) }

        let revalidate: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.controller.revalidateFit() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: revalidate)
        // Without a notch, the status area ends where the frontmost app's menus end.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: revalidate)

        #if DEBUG
        listenForDebugCommands()
        #endif

        if CommandLine.arguments.contains("--diagnose") {
            Task {
                print(await Diagnostics.run(controller: controller).path)
                NSApp.terminate(nil)
            }
            return
        }

        if !Permissions.hasAccessibility {
            Permissions.requestAccessibility()
        }
        if !Settings.didOnboard {
            // Stay fully revealed so the dividers are there to ⌘-drag items around.
            Settings.didOnboard = true
            showHowTo()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await controller.ensureControlOrder()
            }
        } else {
            Task {
                // Let apps publish their items, picture any new ones, then hide.
                try? await Task.sleep(for: .seconds(1.5))
                await controller.ensureControlOrder()
                if await controller.hasItemsWithoutImages() {
                    await controller.refreshImages()
                }
                await controller.apply(.none)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bar.close()
    }

    // MARK: - Clicks

    private static func isSecondaryClick(_ event: NSEvent?) -> Bool {
        event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    }

    private func appIconClicked() {
        bar.close()
        showMenu(under: ControlItems.Identifier.app)
    }

    private func chevronClicked(_ event: NSEvent?) {
        if Self.isSecondaryClick(event) {
            bar.close()
            showMenu(under: ControlItems.Identifier.hidden)
            return
        }
        let includeAlwaysHidden = event?.modifierFlags.contains(.option) == true
        if bar.isVisible || Date().timeIntervalSince(bar.closedAt) < 0.3 {
            bar.close()
            return
        }
        Task {
            if controller.reveal != .none, !controller.holdsEverythingRevealed {
                await controller.apply(.none)
                return
            }
            switch Settings.displayMode {
            case .menuBar:
                await controller.apply(includeAlwaysHidden ? .all : .hidden)
                controller.startRehideTimer()
            case .bar, .list, .grid:
                await openPanel(includeAlwaysHidden: includeAlwaysHidden)
            }
        }
    }

    // MARK: - Panel

    private func openPanel(includeAlwaysHidden: Bool) async {
        let anchor = await controller.chevronFrame()
        guard Permissions.hasAccessibility else {
            presentPanel(entries: [], message: "baaar needs Accessibility access — click the baaar icon", anchor: anchor)
            return
        }
        let sections: Set<MenuBarSection> = includeAlwaysHidden ? [.hidden, .alwaysHidden] : [.hidden]
        let items = await controller.items(in: sections)
        let entries = items.map { BarEntry(item: $0, image: controller.images.image(for: $0)) }
        presentPanel(entries: entries, message: entries.isEmpty ? "Nothing hidden — ⌘-drag icons to the left of ‹" : nil, anchor: anchor)
    }

    private func presentPanel(entries: [BarEntry], message: String?, anchor: CGRect?) {
        bar.show(
            entries: entries,
            message: message,
            mode: Settings.displayMode,
            anchor: anchor,
            screen: controls.screen,
            appearance: controls.appItem.button?.effectiveAppearance
        )
    }

    private func activate(_ item: MenuBarItem) {
        bar.close()
        Task { await controller.activate(item.id) }
    }

    // MARK: - Menu

    private func showMenu(under identifier: String) {
        let menu = NSMenu()
        if controller.reveal == .none {
            addItem(to: menu, "Show Hidden Items", #selector(menuShowHidden))
            addItem(to: menu, "Show All Items", #selector(menuShowAll))
        } else {
            addItem(to: menu, "Hide Items", #selector(menuHide))
        }
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let item = addItem(to: modeMenu, mode.title, #selector(menuSelectMode(_:)))
            item.representedObject = mode.rawValue
            item.state = Settings.displayMode == mode ? .on : .off
        }
        menu.addItem(withTitle: "Show Hidden Items", action: nil, keyEquivalent: "").submenu = modeMenu
        addItem(to: menu, "Edit Layout…", #selector(menuEditLayout), key: ",")
        addItem(to: menu, "Refresh Icons", #selector(menuRefreshImages))
        menu.addItem(.separator())

        addItem(to: menu, "Launch at Login", #selector(menuToggleLaunchAtLogin)).state = Settings.launchesAtLogin ? .on : .off
        addItem(to: menu, "How to Use baaar…", #selector(showHowTo))
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
            let snapshot = await ItemScanner.scan(.controls)
            guard let frame = snapshot.own(identifier)?.frame, let screen = controls.screen,
                  let primaryHeight = NSScreen.screens.first?.frame.height else { return }
            // A collapsed chevron is wide; centre on the glyph at its right edge.
            let centerX = identifier == ControlItems.Identifier.hidden ? frame.maxX - min(frame.width, 28) / 2 : frame.midX
            // With no view the location is in screen coordinates and marks the menu's top-left corner.
            // It must sit below the menu bar, or AppKit clips the menu and adds a scroll arrow.
            let top = min(primaryHeight - frame.maxY, screen.visibleFrame.maxY) - 2
            menu.popUp(positioning: nil, at: NSPoint(x: centerX - menu.size.width / 2, y: top), in: nil)
        }
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuShowHidden() {
        Task { await controller.apply(.hidden); controller.startRehideTimer() }
    }

    @objc private func menuShowAll() {
        Task { await controller.apply(.all); controller.startRehideTimer() }
    }

    @objc private func menuHide() {
        Task { await controller.apply(.none) }
    }

    @objc private func menuSelectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        Settings.displayMode = mode
    }

    @objc private func menuEditLayout() {
        editor.show()
    }

    @objc private func menuRefreshImages() {
        Task { await controller.refreshImages() }
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
            let url = await Diagnostics.run(controller: controller)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func showHowTo() {
        let alert = NSAlert()
        alert.messageText = "Hide icons with baaar"
        alert.informativeText = """
        baaar adds two icons: the ‹ chevron, which hides and shows, and the baaar icon, which holds every setting.

        Hold ⌘ and drag menu bar icons to the left of the chevron to hide them, or further left of the thin divider to keep them always hidden. You can also drag them between sections in Edit Layout.

        Click the chevron to see hidden icons; ⌥-click it to include the always-hidden ones. Choose how they appear — in the menu bar, a bar, a list or a grid — from the baaar icon.
        """
        alert.addButton(withTitle: "Got It")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - Debug

    #if DEBUG
    /// Lets scripts drive the app through distributed notifications named `com.aaangelmartin.baaar.debug.<command>`,
    /// with an optional string argument as the notification object.
    private func listenForDebugCommands() {
        let commands: [String: @MainActor (AppDelegate, String?) async -> Void] = [
            "hide": { app, _ in await app.controller.apply(.none) },
            "show": { app, _ in await app.controller.apply(.hidden) },
            "all": { app, _ in await app.controller.apply(.all) },
            "refresh": { app, _ in await app.controller.refreshImages() },
            "chevron": { app, _ in app.chevronClicked(nil) },
            "panel": { app, argument in await app.openPanel(includeAlwaysHidden: argument == "all") },
            "close": { app, _ in app.bar.close() },
            "menu": { app, argument in app.showMenu(under: argument == "app" ? ControlItems.Identifier.app : ControlItems.Identifier.hidden) },
            "mode": { _, argument in Settings.displayMode = DisplayMode(rawValue: argument ?? "") ?? .bar },
            "editor": { app, _ in app.editor.show() },
            "press": { app, bundleID in
                let item = await ItemScanner.scan().items.first { $0.bundleIdentifier == bundleID && $0.isManageable }
                if let item { await app.controller.activate(item.id) }
            },
            // "<bundle id>:<section>"
            "move": { app, argument in
                let parts = (argument ?? "").split(separator: ":").map(String.init)
                guard parts.count == 2, let destination = MenuBarSection(rawValue: parts[1]),
                      let item = await ItemScanner.scan().items.first(where: { $0.bundleIdentifier == parts[0] && $0.isManageable }) else { return }
                let moved = await app.controller.move(item.id, to: destination)
                Log.write("move \(item.id) to \(destination.rawValue): \(moved)")
            },
            "escape": { _, _ in
                for keyDown in [true, false] {
                    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: keyDown)?.post(tap: .cghidEventTap)
                }
            },
            "clickentry": { app, argument in
                let frames = app.bar.debugItemFrames
                guard let index = Int(argument ?? ""), frames.indices.contains(index),
                      let primaryHeight = NSScreen.screens.first?.frame.height else { return }
                SyntheticInput.click(at: CGPoint(x: frames[index].midX, y: primaryHeight - frames[index].midY))
            },
        ]
        for (name, command) in commands {
            DistributedNotificationCenter.default().addObserver(forName: .init("com.aaangelmartin.baaar.debug.\(name)"), object: nil, queue: .main) { [weak self] note in
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
