import AppKit
import SwiftUI

/// Owns the settings window. baaar is a menu bar app, so it becomes a regular app only while the window is open.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show(pane: SettingsPane = .general) {
        navigation.pane = pane
        let window = window ?? makeWindow()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        reloadModel()
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

        let hostingView = NSHostingView(rootView: SettingsView(model: model, navigation: navigation))
        hostingView.sceneBridgingOptions = [.toolbars]
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()

        self.window = window
        return window
    }

    private func reloadModel() {
        Task { await model.reload() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reloadModel()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
