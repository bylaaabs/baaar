import AppKit
import ApplicationServices

/// An `AXUIElement` that can cross to the scanning queue.
///
/// Accessibility elements are immutable CF references and the AX API is safe to
/// call from any thread, so sharing them is sound.
struct AXElement: @unchecked Sendable, Hashable {
    let raw: AXUIElement
}

/// A status item found in some app's `AXExtrasMenuBar`.
struct MenuBarItem: Sendable, Identifiable, Hashable {
    /// Stable across scans and state changes: the bundle plus the item's `AXIdentifier` or its index in the app.
    let id: String
    let element: AXElement
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// The item's title or description, if it has one.
    let label: String?
    /// Frame in global screen coordinates with a top-left origin, as AX reports it.
    ///
    /// Items macOS isn't drawing (concealed or overflowed) keep reporting a stale frame.
    let frame: CGRect?
    /// Third-party items are `AXMenuBarItem`s; MenuBarAgent's own groups cannot be pressed.
    let isPressable: Bool
    let isOwn: Bool

    var displayName: String {
        guard let label, label != appName else { return appName }
        // Apple's extras run in helper processes with names like "WeatherMenu"; their label reads better.
        if bundleIdentifier?.hasPrefix("com.apple.") == true { return label }
        return appName
    }

    var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    /// Items baaar can hide and show: other apps' pressable items.
    var isManageable: Bool {
        isPressable && !isOwn && bundleIdentifier != nil
    }
}

/// One pass over the menu bar.
struct MenuBarSnapshot: Sendable {
    var items: [MenuBarItem]
    /// macOS 27's native "Show Hidden Menu Bar Items" chevron, present while items overflow.
    var overflowButtonFrame: CGRect?

    func item(id: String) -> MenuBarItem? {
        items.first { $0.id == id }
    }

    /// Whether the item is actually drawn where AX says.
    ///
    /// Concealed and overflowed items keep stale frames that pile up on top of the
    /// overflow chevron and of the items drawn now, so overlaps give them away.
    func isOnScreen(_ item: MenuBarItem, concealed: Set<String>) -> Bool {
        guard let bundle = item.bundleIdentifier, !concealed.contains(bundle) else { return false }
        // Neighbouring items legitimately overlap by a couple of points.
        let slack: CGFloat = 5
        guard let frame = item.frame?.insetBy(dx: slack, dy: 1), frame.width > 0 else { return false }
        if let overflowButtonFrame, frame.intersects(overflowButtonFrame) { return false }
        return !items.contains { other in
            guard other.id != item.id, other.isManageable, let otherBundle = other.bundleIdentifier,
                  !concealed.contains(otherBundle), let otherFrame = other.frame else { return false }
            return frame.intersects(otherFrame.insetBy(dx: slack, dy: 1))
        }
    }
}
