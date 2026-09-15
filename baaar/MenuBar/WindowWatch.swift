import AppKit

/// Reads on-screen windows to tell when an item's menu or popover is open.
enum WindowWatch {
    struct Window: Hashable {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        /// Global, top-left origin.
        let bounds: CGRect
    }

    static func onScreen() -> [Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
            return Window(id: id, pid: pid, layer: info[kCGWindowLayer as String] as? Int ?? 0, bounds: bounds)
        }
    }

    /// Menus and popovers that weren't on screen in `baseline` and hang from the top of a screen.
    ///
    /// Apps such as Canopy keep menu-level windows around all the time, so only new
    /// windows count. Pass nil for `pid` to accept any owner: helper processes often own an item's menu.
    static func newPopups(of pid: pid_t?, since baseline: Set<CGWindowID>, screenTop: CGFloat) -> [Window] {
        let reach = screenTop + menuBarHeight + 80
        let cursorLevel = Int(CGWindowLevelForKey(.cursorWindow))
        return onScreen().filter { window in
            (pid == nil || window.pid == pid) && window.layer > 0 && window.layer < cursorLevel
                && !baseline.contains(window.id) && window.bounds.minY <= reach && window.bounds.height > 4
                && window.pid != ProcessInfo.processInfo.processIdentifier
        }
    }

    static func ids() -> Set<CGWindowID> {
        Set(onScreen().map(\.id))
    }

    /// The topmost window under a point in AppKit coordinates.
    static func window(at point: NSPoint) -> Window? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let topLeft = CGPoint(x: point.x, y: primaryHeight - point.y)
        let cursorLevel = Int(CGWindowLevelForKey(.cursorWindow))
        return onScreen().first { $0.layer < cursorLevel && $0.bounds.contains(topLeft) }
    }

    static var menuBarHeight: CGFloat {
        guard let screen = NSScreen.main else { return 38 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
    }
}
