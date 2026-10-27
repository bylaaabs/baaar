import AppKit

/// Hides menu bar items through MenuBarAgent's visibility restriction.
///
/// macOS 27 draws the whole menu bar in one window, so items can no longer be
/// pushed aside. MenuBarAgent instead offers an allow-list assertion (the one
/// assessment mode uses, exposed by the private MenuBarClientCore framework):
/// while it is active only the listed bundles and system items are laid out, and
/// the rest are removed from the bar, freeing their space. Apps are allowed as
/// whole bundles; Apple's items one by one, and only the nine `SystemItem`s. The
/// assertion dies with baaar's connection, so a crash brings every item back.
@MainActor
final class VisibilityRestriction {
    private var assertion: NSObject?
    private var pending: NSObject?
    private var runningObservation: NSKeyValueObservation?
    private var refreshTask: Task<Void, Never>?

    /// App bundles and `SystemItem.key`s currently concealed.
    private(set) var concealedKeys: Set<String> = []
    /// Bundles allowed by the active assertion, to tell whether a newly launched app needs a new one.
    private var allowedBundles: Set<String> = []

    /// Whether this macOS provides the restriction with the selectors baaar calls.
    static let isAvailable: Bool = {
        guard dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != nil,
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion"),
              let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") else { return false }
        return assertionClass.instancesRespond(to: NSSelectorFromString("activateWithConfiguration:completionHandler:"))
            && assertionClass.instancesRespond(to: NSSelectorFromString("invalidate"))
            && configurationClass.instancesRespond(to: NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"))
    }()

    init() {
        // Menu bar apps are usually agents, which don't always post launch notifications; watch the process list instead.
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    /// Conceals the given keys (bundle identifiers and `SystemItem.key`s) and allows everything else running.
    func conceal(_ keys: Set<String>) {
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        concealedKeys = keys.subtracting([ownBundle])
        issue()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            let running = Self.runningBundles()
            let isHolding = assertion != nil || pending != nil
            if isHolding != needsRestriction(running: running) {
                // A concealed bundle launched while nothing was held, or the last one quit.
                issue()
            } else if isHolding, !running.subtracting(allowedBundles).subtracting(concealedKeys).isEmpty {
                // A launched bundle the restriction doesn't know about needs to be allowed.
                issue()
            }
        }
    }

    private static func runningBundles() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Whether anything concealed is on screen to hide: a running bundle or a system item.
    /// Without it no restriction is held, since one also hides Apple modules and blocks Notification Center.
    private func needsRestriction(running: Set<String>) -> Bool {
        !concealedKeys.isDisjoint(with: running) || SystemItem.allCases.contains { concealedKeys.contains($0.key) }
    }

    private func issue() {
        let running = Self.runningBundles()
        guard Self.isAvailable, needsRestriction(running: running) else {
            invalidate(&assertion)
            invalidate(&pending)
            allowedBundles = []
            return
        }
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let allowed = running.union([ownBundle]).subtracting(concealedKeys)
        let systemItems = SystemItem.allCases.filter { !concealedKeys.contains($0.key) }.map { NSNumber(value: $0.rawValue) }
        guard let configuration = Self.makeConfiguration(systemItems: systemItems, bundles: Array(allowed)),
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type else {
            Log.write("visibility restriction unavailable")
            return
        }
        allowedBundles = allowed
        let next = assertionClass.init()
        invalidate(&pending)
        pending = next
        let token = ObjectIdentifier(next)
        unsafeBitCast(next, to: RestrictionAssertion.self).activateWithConfiguration(configuration) { @Sendable [weak self] error in
            let failure = error.map { "\($0)" }
            Task { @MainActor in self?.activated(token, failure: failure) }
        }
    }

    /// Swaps in a new assertion only once it is active, so items never flash between the two.
    private func activated(_ token: ObjectIdentifier, failure: String?) {
        // A newer request superseded this one and already invalidated it.
        guard let next = pending, ObjectIdentifier(next) == token else { return }
        pending = nil
        if let failure {
            Log.write("visibility restriction failed: \(failure)")
            unsafeBitCast(next, to: RestrictionAssertion.self).invalidate()
            return
        }
        invalidate(&assertion)
        assertion = next
    }

    private func invalidate(_ slot: inout NSObject?) {
        if let object = slot {
            unsafeBitCast(object, to: RestrictionAssertion.self).invalidate()
        }
        slot = nil
    }

    private static func makeConfiguration(systemItems: [NSNumber], bundles: [String]) -> AnyObject? {
        guard let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let allocated = configurationClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        // `init…` consumes the allocation and returns a +1 object.
        return allocated.perform(
            NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"),
            with: systemItems,
            with: bundles
        )?.takeRetainedValue()
    }
}

@objc private protocol RestrictionAssertion {
    func activateWithConfiguration(_ configuration: AnyObject, completionHandler: @escaping @Sendable (NSError?) -> Void)
    func invalidate()
}
