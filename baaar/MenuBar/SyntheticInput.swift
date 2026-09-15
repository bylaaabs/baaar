import AppKit

/// Mouse input posted like real hardware events. All points are global, top-left origin.
enum SyntheticInput {
    /// Clicks and puts the cursor back. Used on macOS 27's overflow chevron, which exposes no AX action.
    static func click(at point: CGPoint) {
        let saved = CGEvent(source: nil)?.location
        post(.leftMouseDown, at: point)
        post(.leftMouseUp, at: point)
        if let saved {
            CGWarpMouseCursorPosition(saved)
        }
    }

    /// ⌘-drags a menu bar item, the gesture macOS uses to rearrange the menu bar.
    static func commandDrag(from start: CGPoint, to end: CGPoint) async {
        let saved = CGEvent(source: nil)?.location
        post(.leftMouseDown, at: start, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(150))
        let steps = 20
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress), flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(15))
        }
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseUp, at: end, flags: .maskCommand)
        if let saved {
            CGWarpMouseCursorPosition(saved)
        }
    }

    private static func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags = []) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}
