import AppKit
import ApplicationServices

/// An `AXUIElement` that can cross threads.
///
/// Accessibility elements are immutable CF references and the AX API is safe to
/// call from any thread, so sharing them is sound.
struct AXElement: @unchecked Sendable, Hashable {
    let raw: AXUIElement
}

/// A status item found in some app's `AXExtrasMenuBar`.
struct MenuBarItem: Sendable, Identifiable, Hashable {
    static let menuBarAgent = "com.apple.MenuBarAgent"

    /// Stable across scans and state changes: the bundle plus the item's `AXIdentifier` or its index in the app.
    let id: String
    let element: AXElement
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// The item's title or description, if it has one.
    let label: String?
    /// `AXIdentifier`, e.g. `com.apple.menuextra.clock` for Apple's items.
    let identifier: String?
    /// Frame in global screen coordinates with a top-left origin, as AX reports it.
    ///
    /// Items macOS isn't drawing (concealed or overflowed) keep reporting a stale frame.
    let frame: CGRect?
    let isPressable: Bool
    let isOwn: Bool

    /// Apple's items that MenuBarAgent lets baaar keep or hide one by one.
    var systemItem: SystemItem? {
        guard bundleIdentifier == Self.menuBarAgent, let identifier else { return nil }
        let name = identifier.lowercased()
        return switch true {
        case name.hasSuffix(".battery"): .battery
        case name.hasSuffix(".bluetooth"): .bluetooth
        case name.hasSuffix(".clock"): .clock
        case name.contains("display"): .displays
        case name.contains("keyboard"): .keyboard
        case name.hasSuffix(".sound") || name.hasSuffix(".volume"): .sound
        case name.hasSuffix(".wifi"): .wifi
        case name.contains("screenmirroring") || name.contains("airplay"): .screenMirroring
        case name.hasSuffix(".controlcenter"): .controlCenter
        default: nil
        }
    }

    /// What sections are assigned to: the bundle, or the system item's key for Apple's items.
    var sectionKey: String? {
        systemItem?.key ?? (bundleIdentifier == Self.menuBarAgent ? nil : bundleIdentifier)
    }

    var displayName: String {
        if let systemItem { return systemItem.title }
        guard let label, label != appName else { return appName }
        // Apple's extras run in helper processes with names like "WeatherMenu"; their label reads better.
        if bundleIdentifier?.hasPrefix("com.apple.") == true { return label }
        return appName
    }

    var appIcon: NSImage? {
        systemItem == nil ? NSRunningApplication(processIdentifier: pid)?.icon : nil
    }

    /// Items baaar lists, hides and opens: other apps' items and Apple's system items.
    /// Other Apple modules (Focus, Fast User Switching…) can't be kept visible while anything is hidden.
    var isManageable: Bool {
        isPressable && !isOwn && sectionKey != nil
    }
}

/// One pass over the menu bar.
struct MenuBarSnapshot: Sendable {
    var items: [MenuBarItem]
    /// macOS 27's native "Show Hidden Menu Bar Items" chevron, present while items overflow.
    var overflowButtonFrame: CGRect?
    var takenAt = Date()

    func item(id: String) -> MenuBarItem? {
        items.first { $0.id == id }
    }

    /// Whether the item is actually drawn where AX says.
    ///
    /// Concealed and overflowed items keep stale frames that pile up on top of the
    /// overflow chevron and of the items drawn now, so overlaps give them away.
    func isOnScreen(_ item: MenuBarItem, concealed: Set<String>) -> Bool {
        if let key = item.sectionKey, concealed.contains(key) { return false }
        guard let rawFrame = item.frame, rawFrame.width > 0 else { return false }
        // Neighbouring items legitimately overlap by a couple of points.
        let slack = min(5, rawFrame.width / 4)
        let frame = rawFrame.insetBy(dx: slack, dy: 1)
        if let overflowButtonFrame, frame.intersects(overflowButtonFrame) { return false }
        return !items.contains { other in
            guard other.id != item.id, other.isPressable, let otherFrame = other.frame, otherFrame.width > 0 else { return false }
            if let key = other.sectionKey, concealed.contains(key) { return false }
            let otherSlack = min(5, otherFrame.width / 4)
            return frame.intersects(otherFrame.insetBy(dx: otherSlack, dy: 1))
        }
    }
}
