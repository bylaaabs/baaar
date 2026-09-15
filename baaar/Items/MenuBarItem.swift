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
    /// Stable across scans: owner plus the best name the item exposes.
    let id: String
    let element: AXElement
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// Title, description or help text, whichever the item exposes first.
    let label: String?
    /// Frame in global screen coordinates with a top-left origin, as AX reports it.
    ///
    /// While the item is hidden macOS keeps reporting its last on-screen frame.
    let frame: CGRect?
    /// Third-party items are `AXMenuBarItem`s; MenuBarAgent's own groups cannot be pressed.
    let isPressable: Bool
    let isOwn: Bool

    var displayName: String {
        guard let label, !label.isEmpty, label != appName else { return appName }
        return "\(appName) — \(label)"
    }

    var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}

/// One pass over the menu bar.
struct MenuBarSnapshot: Sendable {
    var items: [MenuBarItem]
    /// macOS 27's native "Show Hidden Menu Bar Items" chevron, when items overflow.
    var overflowButtonFrame: CGRect?

    var ownItems: [MenuBarItem] {
        items.filter(\.isOwn)
    }
}
