import AppKit
import ApplicationServices

/// Reads every app's status items through Accessibility.
///
/// On macOS 27 the menu bar is a single WindowServer window, so per-item windows
/// no longer exist; each app's `AXExtrasMenuBar` is the only public item list.
enum ItemScanner {
    private static let messagingTimeout: Float = 0.25
    private static let queue = DispatchQueue(label: "com.aaangelmartin.baaar.scanner", qos: .userInitiated, attributes: .concurrent)

    /// Scans every app in parallel on a dedicated queue, so blocking AX calls never tie up
    /// Swift's shared thread pool and one slow app only costs its own timeout.
    ///
    /// The main thread must never query baaar's own items: AX requests to our own
    /// process are answered on the main thread, so it would wait on itself.
    static func scan(pids: Set<pid_t>? = nil) async -> MenuBarSnapshot {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { pids?.contains($0.processIdentifier) ?? true }
            .map { AppRef(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "App") }
        return await withCheckedContinuation { continuation in
            queue.async {
                let results = ResultBox(count: apps.count)
                DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                    results.set(index, scan(apps[index], ownPID: ownPID))
                }
                let scans = results.values
                var snapshot = MenuBarSnapshot(items: scans.flatMap(\.items), overflowButtonFrame: scans.lazy.compactMap(\.overflowButtonFrame).first)
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

    private struct AppScan: Sendable {
        var items: [MenuBarItem] = []
        var overflowButtonFrame: CGRect?
    }

    /// Collects per-app results from `concurrentPerform`.
    private final class ResultBox: @unchecked Sendable {
        private var storage: [AppScan]
        private let lock = NSLock()

        init(count: Int) {
            storage = Array(repeating: AppScan(), count: count)
        }

        func set(_ index: Int, _ value: AppScan) {
            lock.withLock { storage[index] = value }
        }

        var values: [AppScan] {
            lock.withLock { storage }
        }
    }

    private static func scan(_ app: AppRef, ownPID: pid_t) -> AppScan {
        var result = AppScan()
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let extras: AXUIElement = AX.value(appElement, "AXExtrasMenuBar") else { return result }
        AXUIElementSetMessagingTimeout(extras, messagingTimeout)
        let owner = app.bundleIdentifier ?? "pid\(app.pid)"
        let children: [AXUIElement] = AX.value(extras, kAXChildrenAttribute) ?? []
        for (index, child) in children.enumerated() {
            AXUIElementSetMessagingTimeout(child, messagingTimeout)
            var element = child
            var role: String? = AX.value(child, kAXRoleAttribute)
            if role == kAXButtonRole {
                result.overflowButtonFrame = AX.frame(child)
                continue
            }
            // MenuBarAgent wraps each of Apple's items in a hosting group; the pressable item is inside.
            if role == kAXGroupRole, let inner = (AX.value(child, kAXChildrenAttribute) as [AXUIElement]?)?.first {
                AXUIElementSetMessagingTimeout(inner, messagingTimeout)
                element = inner
                role = AX.value(inner, kAXRoleAttribute)
            }
            let identifier = (AX.value(element, kAXIdentifierAttribute) as String?)?.nilIfEmpty
            // Titles and help text change with state ("Click to prevent sleep"), so they never go into the id.
            result.items.append(MenuBarItem(
                id: "\(owner)/\(identifier ?? "item\(index)")",
                element: AXElement(raw: element),
                pid: app.pid,
                bundleIdentifier: app.bundleIdentifier,
                appName: app.name,
                label: firstString(of: element, [kAXTitleAttribute, kAXDescriptionAttribute]),
                identifier: identifier,
                frame: AX.frame(element),
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

    /// Presses an item and returns once the owning app is done with it.
    ///
    /// For an item with a menu that is when the menu closes; for a popover or a
    /// window it returns right away. The call runs on its own thread, so an app
    /// that never answers only costs that thread.
    static func press(_ element: AXElement, id: String) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                AXUIElementSetMessagingTimeout(element.raw, 120)
                let result = AXUIElementPerformAction(element.raw, kAXPressAction as CFString)
                if result != .success, result != .cannotComplete {
                    Log.write("press \(id) failed with AXError \(result.rawValue)")
                }
                continuation.resume()
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
