import AppKit
import ApplicationServices

/// Reads every app's status items through Accessibility.
///
/// On macOS 27 the menu bar is a single WindowServer window, so per-item windows
/// no longer exist; each app's `AXExtrasMenuBar` is the only public item list.
enum ItemScanner {
    enum Scope {
        /// Every running app.
        case all
        /// Only baaar and MenuBarAgent: enough to see baaar's dividers and macOS's overflow chevron, fast.
        case controls
    }

    private static let queue = DispatchQueue(label: "com.aaangelmartin.baaar.scanner", qos: .userInitiated)
    private static let menuBarAgent = "com.apple.MenuBarAgent"

    /// Scans off the main thread; a slow app only costs its own messaging timeout.
    ///
    /// The main thread must never query baaar's own items: AX requests to our own
    /// process are answered on the main thread, so it would wait on itself.
    static func scan(_ scope: Scope = .all) async -> MenuBarSnapshot {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { scope == .all || $0.processIdentifier == ownPID || $0.bundleIdentifier == menuBarAgent }
            .map { AppRef(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "App") }
        return await withCheckedContinuation { continuation in
            queue.async {
                var snapshot = MenuBarSnapshot(items: [], overflowButtonFrame: nil)
                for app in apps {
                    scan(app, ownPID: ownPID, into: &snapshot)
                }
                snapshot.items.sort { ($0.frame?.minX ?? -.infinity) < ($1.frame?.minX ?? -.infinity) }
                continuation.resume(returning: snapshot)
            }
        }
    }

    private struct AppRef: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let name: String
    }

    private static func scan(_ app: AppRef, ownPID: pid_t, into snapshot: inout MenuBarSnapshot) {
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        guard let extras: AXUIElement = AX.value(appElement, "AXExtrasMenuBar") else { return }
        let children: [AXUIElement] = AX.value(extras, kAXChildrenAttribute) ?? []
        var occurrences: [String: Int] = [:]
        for child in children {
            let role: String? = AX.value(child, kAXRoleAttribute)
            if role == kAXButtonRole {
                snapshot.overflowButtonFrame = AX.frame(child)
                continue
            }
            let label = firstString(of: child, [kAXTitleAttribute, kAXDescriptionAttribute])
            let identifier: String? = (AX.value(child, kAXIdentifierAttribute) as String?)?.nilIfEmpty
            let key = identifier ?? label ?? firstString(of: child, [kAXHelpAttribute])
            let base = "\(app.bundleIdentifier ?? app.name)/\(key ?? "item")"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            snapshot.items.append(MenuBarItem(
                id: occurrence == 0 ? base : "\(base)#\(occurrence)",
                element: AXElement(raw: child),
                pid: app.pid,
                bundleIdentifier: app.bundleIdentifier,
                appName: app.name,
                label: label,
                identifier: identifier,
                frame: AX.frame(child),
                isPressable: role == "AXMenuBarItem",
                isOwn: app.pid == ownPID
            ))
        }
    }
}

private func firstString(of element: AXUIElement, _ attributes: [String]) -> String? {
    attributes.lazy
        .compactMap { (AX.value(element, $0) as String?)?.nilIfEmpty }
        .first
        .map { $0.components(separatedBy: .newlines)[0] }
}

enum AX {
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// AX frame in global coordinates, top-left origin.
    static func frame(_ element: AXUIElement) -> CGRect? {
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

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    /// Presses an item and returns once the owning app has handled it.
    ///
    /// For a status item with a menu that is when the menu closes, so this can
    /// take as long as the user keeps the menu open. It runs off the main thread.
    static func press(_ element: AXElement) async -> AXError {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                AXUIElementSetMessagingTimeout(element.raw, 120)
                continuation.resume(returning: AXUIElementPerformAction(element.raw, kAXPressAction as CFString))
            }
        }
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
