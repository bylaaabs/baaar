import AppKit
import ApplicationServices

/// Reads every app's status items through Accessibility.
///
/// On macOS 27 the menu bar is a single WindowServer window, so per-item windows
/// no longer exist; each app's `AXExtrasMenuBar` is the only public item list.
enum ItemScanner {
    private static let messagingTimeout: Float = 0.25

    /// Scans every app concurrently, off the main thread; a slow app only costs its own timeout.
    ///
    /// The main thread must never query baaar's own items: AX requests to our own
    /// process are answered on the main thread, so it would wait on itself.
    static func scan(pids: Set<pid_t>? = nil) async -> MenuBarSnapshot {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { pids?.contains($0.processIdentifier) ?? true }
            .map { AppRef(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "App") }
        let results = await withTaskGroup(of: AppScan.self) { group in
            for app in apps {
                group.addTask { scan(app, ownPID: ownPID) }
            }
            return await group.reduce(into: [AppScan]()) { $0.append($1) }
        }
        var snapshot = MenuBarSnapshot(items: results.flatMap(\.items), overflowButtonFrame: results.lazy.compactMap(\.overflowButtonFrame).first)
        snapshot.items.sort { ($0.frame?.minX ?? -.infinity) < ($1.frame?.minX ?? -.infinity) }
        return snapshot
    }

    private struct AppRef: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let name: String
    }

    private struct AppScan: Sendable {
        var items: [MenuBarItem] = []
        var overflowButtonFrame: CGRect?
    }

    private nonisolated static func scan(_ app: AppRef, ownPID: pid_t) -> AppScan {
        var result = AppScan()
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let extras: AXUIElement = AX.value(appElement, "AXExtrasMenuBar") else { return result }
        AXUIElementSetMessagingTimeout(extras, messagingTimeout)
        let children: [AXUIElement] = AX.value(extras, kAXChildrenAttribute) ?? []
        for (index, child) in children.enumerated() {
            AXUIElementSetMessagingTimeout(child, messagingTimeout)
            let role: String? = AX.value(child, kAXRoleAttribute)
            if role == kAXButtonRole {
                result.overflowButtonFrame = AX.frame(child)
                continue
            }
            let identifier = (AX.value(child, kAXIdentifierAttribute) as String?)?.nilIfEmpty
            // Titles and help text change with state ("Click to prevent sleep"), so they never go into the id.
            let owner = app.bundleIdentifier ?? "pid\(app.pid)"
            result.items.append(MenuBarItem(
                id: "\(owner)/\(identifier ?? "item\(index)")",
                element: AXElement(raw: child),
                pid: app.pid,
                bundleIdentifier: app.bundleIdentifier,
                appName: app.name,
                label: firstString(of: child, [kAXTitleAttribute, kAXDescriptionAttribute]),
                frame: AX.frame(child),
                isPressable: role == "AXMenuBarItem",
                isOwn: app.pid == ownPID
            ))
        }
        return result
    }
}

private func firstString(of element: AXUIElement, _ attributes: [String]) -> String? {
    attributes.lazy
        .compactMap { (AX.value(element, $0) as String?)?.nilIfEmpty }
        .first
        .map { $0.components(separatedBy: .newlines)[0] }
}

enum AX {
    nonisolated static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// AX frame in global coordinates, top-left origin.
    nonisolated static func frame(_ element: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            let positionValue = axValue(element, kAXPositionAttribute),
            let sizeValue = axValue(element, kAXSizeAttribute),
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    nonisolated static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    /// Presses an item without waiting for it.
    ///
    /// `AXPress` only returns once the owning app is done, which for a status item
    /// with a menu is when the menu closes, so it runs on its own thread and baaar
    /// watches the app's windows instead.
    nonisolated static func press(_ element: AXElement, id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementSetMessagingTimeout(element.raw, 120)
            let result = AXUIElementPerformAction(element.raw, kAXPressAction as CFString)
            if result != .success, result != .cannotComplete {
                Log.write("press \(id) failed with AXError \(result.rawValue)")
            }
        }
    }

    private nonisolated static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
