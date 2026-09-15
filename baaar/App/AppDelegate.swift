import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController!
    private var settingsWindow: SettingsWindowController!
    private let model = AppModel()
    private let bar = BarController()

    private var controls: ControlItems {
        controller.controls
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.migrateLegacySections()
        controller = MenuBarController(controls: ControlItems())
        model.controller = controller
        settingsWindow = SettingsWindowController(model: model)
        controls.onAppClick = { [weak self] event in self?.appIconClicked(event) }
        controls.onChevronClick = { [weak self] event in self?.chevronClicked(event) }
        bar.onSelect = { [weak self] item in
            self?.bar.close()
            self?.controller.activate(item)
        }
        bar.onClose = { [weak self] in
            self?.controller.isPanelOpen = false
        }

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
        if !VisibilityRestriction.isAvailable {
            Log.write("MenuBarAgent's visibility restriction is unavailable; items can't be hidden")
        }
        Task {
            await controller.refreshSnapshot()
            // Hide right away when every hidden item already has a picture; otherwise picture them first.
            controller.setReveal(.none)
            if await controller.hasHiddenItemsWithoutImages() {
                await controller.refreshImages(onlyMissing: true)
            }
            if !Settings.didOnboard {
                Settings.didOnboard = true
                settingsWindow.show(pane: .layout)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        bar.close()
    }

    // MARK: - Clicks

    /// Status item actions fire on mouse up; anything else (VoiceOver, a stale event) counts as a primary click.
    private static func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseUp || event.type == .rightMouseDown
            || (event.type == .leftMouseUp && (event.modifierFlags.contains(.control) || NSEvent.modifierFlags.contains(.control)))
    }

    private func appIconClicked(_ event: NSEvent?) {
        bar.close()
        showMenu(under: ControlItems.Identifier.app)
    }

    private func chevronClicked(_ event: NSEvent?) {
        Log.write("chevron click type=\(String(describing: event?.type.rawValue)) flags=\(String(describing: event?.modifierFlags.rawValue))")
        if Self.isSecondaryClick(event) {
            bar.close()
            showMenu(under: ControlItems.Identifier.chevron)
            return
        }
        if bar.isVisible || Date().timeIntervalSince(bar.closedAt) < 0.3 {
            bar.close()
            return
        }
        if controller.reveal != .none {
            controller.setReveal(.none)
            return
        }
        // MenuBarAgent forwards status item clicks, and the forwarded event may not carry modifiers; read the keyboard instead.
        let includeAlwaysHidden = NSEvent.modifierFlags.contains(.option) || event?.modifierFlags.contains(.option) == true
        showHiddenItems(includeAlwaysHidden: includeAlwaysHidden)
    }

    /// Shows hidden items the way the user chose: in place, or in a bar, list or grid.
    private func showHiddenItems(includeAlwaysHidden: Bool) {
        switch Settings.displayMode {
        case .menuBar:
            controller.setReveal(includeAlwaysHidden ? .all : .hidden)
            controller.startRehideMonitor()
        case .bar, .list, .grid:
            guard Permissions.hasAccessibility else {
                settingsWindow.show(pane: .permissions)
                return
            }
            openPanel(includeAlwaysHidden: includeAlwaysHidden)
        }
    }

    // MARK: - Panel

    /// Opens straight from the last scan, then refreshes it in the background.
    private func openPanel(includeAlwaysHidden: Bool) {
        let sections: Set<MenuBarSection> = includeAlwaysHidden ? [.hidden, .alwaysHidden] : [.hidden]
        presentPanel(items: controller.items(in: sections), snapshot: controller.snapshot)
        Task {
            let fresh = await controller.refreshSnapshot()
            let items = controller.items(in: sections, from: fresh)
            guard bar.isVisible, items.map(\.id) != bar.shownItemIDs else { return }
            presentPanel(items: items, snapshot: fresh)
        }
    }

    private func presentPanel(items: [MenuBarItem], snapshot: MenuBarSnapshot) {
        let entries = items.map { BarEntry(item: $0, image: controller.images.image(for: $0)) }
        let message = entries.isEmpty ? "Nothing hidden yet - open Settings to hide items" : nil
        bar.show(entries: entries, message: message, mode: Settings.displayMode, anchor: Self.ownFrame(ControlItems.Identifier.chevron, in: snapshot), screen: controls.screen, appearance: controls.menuBarAppearance)
        controller.isPanelOpen = true
    }

    /// One of baaar's own status items in AppKit screen coordinates, from a scan.
    private static func ownFrame(_ identifier: String, in snapshot: MenuBarSnapshot) -> CGRect? {
        guard let frame = snapshot.items.first(where: { $0.isOwn && $0.identifier == identifier })?.frame,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
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
        menu.addItem(withTitle: "Show Hidden Items As", action: nil, keyEquivalent: "").submenu = modeMenu
        addItem(to: menu, "Refresh Icons", #selector(menuRefreshImages))
        addItem(to: menu, "Settings…", #selector(menuSettings), key: ",")
        menu.addItem(.separator())
        addItem(to: menu, "Quit baaar", #selector(NSApplication.terminate(_:)), key: "q").target = NSApp

        guard let anchor = Self.ownFrame(identifier, in: controller.snapshot), let screen = controls.screen else {
            if let button = (identifier == ControlItems.Identifier.app ? controls.appItem : controls.chevronItem).button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
            }
            return
        }
        // With no view the location is in screen coordinates and marks the menu's top-left corner.
        // It must sit below the menu bar, or AppKit clips the menu and adds a scroll arrow.
        let top = min(anchor.minY, screen.visibleFrame.maxY) - 2
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.midX - menu.size.width / 2, y: top), in: nil)
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuShowHidden() {
        showHiddenItems(includeAlwaysHidden: false)
    }

    @objc private func menuShowAll() {
        showHiddenItems(includeAlwaysHidden: true)
    }

    @objc private func menuHide() {
        controller.setReveal(.none)
    }

    @objc private func menuSelectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        bar.close()
        model.displayMode = mode
    }

    @objc private func menuRefreshImages() {
        Task { await model.refreshIcons() }
    }

    @objc private func menuSettings() {
        settingsWindow.show()
    }

    // MARK: - Debug

    #if DEBUG
    /// Lets scripts drive the app through distributed notifications named `com.aaangelmartin.baaar.debug.<command>`,
    /// with an optional string argument as the notification object.
    private func listenForDebugCommands() {
        let commands: [String: @MainActor (AppDelegate, String?) async -> Void] = [
            "reveal": { app, argument in
                let reveal: Reveal = switch argument { case "all": .all; case "hidden": .hidden; default: .none }
                app.controller.setReveal(reveal)
            },
            "chevron": { app, _ in app.chevronClicked(nil) },
            "showall": { app, _ in app.menuShowAll() },
            "panel": { app, argument in app.openPanel(includeAlwaysHidden: argument == "all") },
            "close": { app, _ in app.bar.close() },
            "menu": { app, argument in app.showMenu(under: argument == "app" ? ControlItems.Identifier.app : ControlItems.Identifier.chevron) },
            "mode": { app, argument in app.model.displayMode = DisplayMode(rawValue: argument ?? "") ?? .bar },
            "refresh": { app, _ in await app.model.refreshIcons() },
            "settings": { app, argument in app.settingsWindow.show(pane: SettingsPane(rawValue: argument ?? "") ?? .general) },
            // "<bundle id>:<section>"
            "section": { app, argument in
                let parts = (argument ?? "").split(separator: ":").map(String.init)
                guard parts.count == 2, let section = MenuBarSection(rawValue: parts[1]) else { return }
                app.controller.setSection(section, forBundle: parts[0])
            },
            "press": { app, bundleID in
                let item = await ItemScanner.scan().items.first { ($0.bundleIdentifier == bundleID || $0.id == bundleID) && $0.isManageable }
                if let item { app.controller.activate(item) }
            },
            "clickentry": { app, argument in
                let frames = app.bar.debugItemFrames
                guard let index = Int(argument ?? ""), frames.indices.contains(index),
                      let primaryHeight = NSScreen.screens.first?.frame.height else { return }
                let point = CGPoint(x: frames[index].midX, y: primaryHeight - frames[index].midY)
                let saved = CGEvent(source: nil)?.location
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                }
                if let saved { CGWarpMouseCursorPosition(saved) }
            },
            "optionclick": { app, _ in
                guard let frame = AppDelegate.ownFrame(ControlItems.Identifier.chevron, in: app.controller.snapshot),
                      let primaryHeight = NSScreen.screens.first?.frame.height else { return }
                let point = CGPoint(x: frame.midX, y: primaryHeight - frame.midY)
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                    event?.flags = .maskAlternate
                    event?.post(tap: .cghidEventTap)
                }
            },
            "escape": { _, _ in
                for keyDown in [true, false] {
                    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: keyDown)?.post(tap: .cghidEventTap)
                }
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
