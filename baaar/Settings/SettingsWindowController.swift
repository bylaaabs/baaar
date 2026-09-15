import AppKit
import SwiftUI

/// Owns the settings window. baaar lives in the menu bar, so it becomes a regular process with a Dock icon only while the window is open.
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
        let hosting = NSHostingController(rootView: SettingsView(model: model, reloader: reloader, navigation: navigation))
        // Fill the whole window, under the transparent titlebar, so the view draws its own title
        // row with the traffic lights floating on top instead of leaving a grey band.
        hosting.safeAreaRegions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "baaar settings"
        window.applyBrandChrome(titleVisible: false, fullSizeContent: true)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 660, height: 460)
        window.delegate = self
        window.setContentSize(NSSize(width: 760, height: 540))
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

    /// Without a main menu ⌘W and ⌘Q do nothing, so install the essentials while the window is open.
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
        appMenu.addItem(item("about baaar", #selector(showAbout(_:)), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("settings\u{2026}", #selector(showSettings(_:)), key: ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("hide baaar", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("quit baaar", #selector(NSApplication.terminate(_:)), key: "q"))

        let fileMenu = NSMenu(title: "file")
        fileMenu.addItem(item("close", #selector(NSWindow.performClose(_:)), key: "w"))

        let editMenu = NSMenu(title: "edit")
        editMenu.addItem(item("cut", #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("copy", #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("paste", #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("select all", #selector(NSText.selectAll(_:)), key: "a"))

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
