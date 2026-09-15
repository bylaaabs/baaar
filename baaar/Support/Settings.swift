import Foundation
import ServiceManagement

@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    enum BarLayout: String, CaseIterable {
        /// A row of icons under the baaar icon, like the Ice Bar.
        case horizontal
        /// A list with each icon and its app name.
        case vertical
    }

    private enum Key {
        static let hidden = "hidden"
        static let dividerMinX = "dividerMinX"
        static let didOnboard = "didOnboard"
        static let barLayout = "barLayout"
    }

    static var barLayout: BarLayout {
        get { defaults.string(forKey: Key.barLayout).flatMap(BarLayout.init(rawValue:)) ?? .horizontal }
        set { defaults.set(newValue.rawValue, forKey: Key.barLayout) }
    }

    /// Whether the hidden section was hidden when baaar last ran.
    static var hidden: Bool {
        get { defaults.bool(forKey: Key.hidden) }
        set { defaults.set(newValue, forKey: Key.hidden) }
    }

    /// Where the divider sat the last time the section was shown, in AX coordinates.
    ///
    /// Hidden items keep reporting their last frame, so comparing against this
    /// value tells which of them belong to the hidden section.
    static var dividerMinX: CGFloat? {
        get { defaults.object(forKey: Key.dividerMinX) as? CGFloat }
        set { defaults.set(newValue, forKey: Key.dividerMinX) }
    }

    static var didOnboard: Bool {
        get { defaults.bool(forKey: Key.didOnboard) }
        set { defaults.set(newValue, forKey: Key.didOnboard) }
    }

    static var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("baaar: launch at login change failed: \(error)")
            }
        }
    }
}
