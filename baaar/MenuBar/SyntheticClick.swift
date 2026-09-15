import CoreGraphics

enum SyntheticClick {
    /// Clicks at a point in global top-left coordinates and puts the cursor back.
    ///
    /// Used on macOS 27's overflow chevron, which exposes no AX action.
    static func click(at point: CGPoint) {
        let saved = CGEvent(source: nil)?.location
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if let saved {
            CGWarpMouseCursorPosition(saved)
        }
    }
}
