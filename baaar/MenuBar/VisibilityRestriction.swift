import AppKit

/// Hides other apps' menu bar items through MenuBarAgent's visibility restriction.
///
/// macOS 27 draws the whole menu bar in one window, so items can no longer be
/// pushed aside. MenuBarAgent instead offers an allow-list assertion (the one
/// assessment mode uses, exposed by the private MenuBarClientCore framework):
/// while it is active only the listed bundles and system items are laid out, and
/// the rest are removed from the bar, freeing their space. The unit is the app
/// bundle, not the single item. The assertion dies with baaar's connection, so a
/// crash brings every item back.
@MainActor
final class VisibilityRestriction {
    /// MBSystemItemIdentifier raw values: battery, bluetooth, clock, displays, keyboard,
    /// volume, wifi, screen mirroring and Control Center. Other Apple modules can't be allowed.
    private static let systemItems = (0...8).map { NSNumber(value: $0) }

    private var assertion: NSObject?
    private(set) var concealedBundles: Set<String> = []

    /// Whether this macOS provides the restriction.
    static let isAvailable: Bool = {
        dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != nil
            && NSClassFromString("MBAssessmentModeAssertion") != nil
            && NSClassFromString("MBAssessmentModeConfiguration") != nil
    }()

    /// Conceals the given bundles and allows every other running app.
    func conceal(_ bundles: Set<String>) {
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let concealed = bundles.subtracting([ownBundle])
        guard concealed != concealedBundles || (assertion == nil) != concealed.isEmpty else { return }
        concealedBundles = concealed
        guard !concealed.isEmpty, Self.isAvailable else {
            release()
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let allowed = running.union([ownBundle]).subtracting(concealed)
        activate(allowedBundles: Array(allowed))
    }

    /// Re-issues the restriction so apps launched since are allowed.
    func refreshAllowedApps() {
        guard !concealedBundles.isEmpty else { return }
        let concealed = concealedBundles
        concealedBundles = []
        conceal(concealed)
    }

    func release() {
        if let assertion {
            unsafeBitCast(assertion, to: RestrictionAssertion.self).invalidate()
        }
        assertion = nil
        concealedBundles = []
    }

    private func activate(allowedBundles: [String]) {
        guard let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let allocated = configurationClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let configuration = allocated.perform(
                  NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"),
                  with: Self.systemItems,
                  with: allowedBundles
              )?.takeUnretainedValue()
        else {
            Log.write("visibility restriction unavailable")
            return
        }
        // Activate the new assertion before dropping the old one, so hidden items never flash.
        let next = assertionClass.init()
        unsafeBitCast(next, to: RestrictionAssertion.self).activateWithConfiguration(configuration) { error in
            if let error {
                Log.write("visibility restriction failed: \(error)")
            }
        }
        if let assertion {
            unsafeBitCast(assertion, to: RestrictionAssertion.self).invalidate()
        }
        assertion = next
    }
}

@objc private protocol RestrictionAssertion {
    func activateWithConfiguration(_ configuration: AnyObject, completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}
