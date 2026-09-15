import AppKit

/// The divider length that pushes the hidden section out of the menu bar.
enum HideLength {
    /// Measured on macOS 27: a divider wider than the room left of it is sent to the
    /// overflow together with every item to its left, but a divider wider than about
    /// 48% of the screen is dropped on its own and nothing else moves. 45% lands
    /// between both limits on every screen width where the status area is capped.
    static let macOS27ScreenFraction = 0.45

    static func value(for screen: NSScreen?) -> CGFloat {
        guard #available(macOS 27, *) else {
            // Up to macOS 26 an oversized item simply pushes its neighbours off screen.
            return 10_000
        }
        let width = screen?.frame.width ?? 1440
        let override = UserDefaults.standard.double(forKey: "hideLengthScreenFraction")
        let fraction = override > 0 ? override : macOS27ScreenFraction
        return (width * fraction).rounded()
    }
}
