import AppKit
import SwiftUI

/// Owns the settings window. baaar is a menu bar app, so it becomes a regular app only while the window is open.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let reloader: ModelReloader
    private let navigation = SettingsNavigation()
    private var window: NSWindow?
    /// The menu in place before the window opened, restored when it closes. `nil` while no menu of ours is installed.
    private var previousMainMenu: NSMenu??

    init(model: AppModel) {
        self.model = model
        reloader = ModelReloader(model: model)
        super.init()
    }

    func show(pane: SettingsPane = .general) {
        navigation.pane = pane
        let window = window ?? makeWindow()

        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        reloader.reloadIfStale()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "baaar Settings"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 640, height: 440)
        window.delegate = self

        let hostingView = NSHostingView(rootView: SettingsView(model: model, reloader: reloader, navigation: navigation))
        hostingView.sceneBridgingOptions = [.toolbars]
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()

        self.window = window
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reloader.reloadIfStale()
    }

    func windowWillClose(_ notification: Notification) {
        restoreMainMenu()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Main menu

    /// A regular app with no main menu ignores ⌘W and ⌘Q, so give it the essentials while the window is open.
    private func installMainMenu() {
        guard previousMainMenu == nil else { return }
        previousMainMenu = .some(NSApp.mainMenu)
        NSApp.mainMenu = makeMainMenu()
    }

    private func restoreMainMenu() {
        guard let previous = previousMainMenu else { return }
        NSApp.mainMenu = previous
        previousMainMenu = nil
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu(title: "baaar")
        appMenu.addItem(item("About baaar", #selector(showAbout(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings(_:)), key: ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide baaar", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit baaar", #selector(NSApplication.terminate(_:)), key: "q"))

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))

        let mainMenu = NSMenu(title: "Main Menu")
        for submenu in [appMenu, fileMenu, editMenu] {
            let holder = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            holder.submenu = submenu
            mainMenu.addItem(holder)
        }
        return mainMenu
    }

    /// A menu item sent to `target`, or down the responder chain when `target` is nil.
    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    @objc private func showAbout(_ sender: Any?) {
        show(pane: .about)
    }

    @objc private func showSettings(_ sender: Any?) {
        show(pane: navigation.pane)
    }
}

/// Coalesces reloads of the model so the menu bar is re-read at most once per second.
@MainActor
final class ModelReloader {
    private let model: AppModel
    private let interval: Duration = .seconds(1)
    private var lastReload: ContinuousClock.Instant?
    private var needsReload = false
    private var worker: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// Reloads now, or once the interval since the last reload has passed. Requests meanwhile share that reload.
    func request() {
        needsReload = true
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.drain() }
    }

    /// Reloads only if nothing reloaded, or is about to, within the interval. For the window coming forward.
    func reloadIfStale() {
        guard worker == nil else { return }
        if let lastReload, ContinuousClock.now < lastReload + interval { return }
        request()
    }

    private func drain() async {
        while needsReload {
            if let lastReload {
                try? await Task.sleep(until: lastReload + interval, clock: .continuous)
            }
            needsReload = false
            lastReload = .now
            await model.reload()
        }
        worker = nil
    }
}
