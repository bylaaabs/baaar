import AppKit

/// What the bar shows for one hidden item.
struct BarEntry {
    let item: MenuBarItem
    /// The captured item, or nil to fall back to the app icon.
    let image: NSImage?
}

/// The floating strip under the menu bar that lists the hidden items.
@MainActor
final class BarController {
    var onSelect: ((MenuBarItem) -> Void)?

    private var panel: BarPanel?
    private var monitors: [Any] = []

    /// When the bar last closed. Clicking the toggle first dismisses the bar through
    /// the panel losing key status, so the click must not reopen it straight away.
    private(set) var closedAt = Date.distantPast

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// - Parameters:
    ///   - anchor: The toggle's window frame; the bar hangs from its right edge.
    ///   - appearance: The menu bar's appearance, so captured icons stay legible.
    func show(entries: [BarEntry], message: String?, anchor: CGRect?, screen: NSScreen?, appearance: NSAppearance?) {
        close()
        guard let screen = screen ?? NSScreen.main else { return }

        let content = NSStackView()
        content.orientation = .horizontal
        content.spacing = 2
        content.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        for entry in entries {
            let button = BarItemButton(entry: entry)
            button.onPress = { [weak self] in self?.onSelect?(entry.item) }
            content.addArrangedSubview(button)
        }
        if let message {
            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            content.addArrangedSubview(label)
        }

        let glass = NSGlassEffectView()
        glass.cornerRadius = 14
        glass.contentView = content

        let size = content.fittingSize
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let maxWidth = screen.frame.width - 16
        let width = min(max(size.width, 44), maxWidth)
        let right = min(anchor?.maxX ?? screen.frame.maxX - 8, screen.frame.maxX - 8)
        let x = max(screen.frame.minX + 8, right - width)
        let y = screen.frame.maxY - menuBarHeight - 6 - size.height
        let frame = NSRect(x: x, y: y, width: width, height: size.height)

        let panel = BarPanel(contentRect: frame)
        panel.appearance = appearance
        panel.contentView = glass
        panel.onCancel = { [weak self] in self?.close() }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        // Any click outside baaar dismisses the bar, like a menu.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            monitors.append(monitor)
        }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        guard let panel else { return }
        self.panel = nil
        panel.onCancel = nil
        panel.orderOut(nil)
        closedAt = Date()
    }
}

private final class BarPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onCancel?()
    }
}

private final class BarItemButton: NSControl {
    var onPress: (() -> Void)?

    private let imageView = NSImageView()
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(entry: BarEntry) {
        let height: CGFloat = 26
        let imageSize: NSSize
        if let image = entry.image {
            imageView.image = image
            imageSize = NSSize(width: image.size.width * min(1, height / max(image.size.height, 1)), height: min(image.size.height, height))
        } else {
            imageView.image = entry.item.appIcon
            imageSize = NSSize(width: 18, height: 18)
        }
        let width = max(imageSize.width, 22) + 6
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        toolTip = entry.item.displayName
        setAccessibilityRole(.button)
        setAccessibilityLabel(entry.item.displayName)

        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = NSRect(
            x: (width - imageSize.width) / 2,
            y: (height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        addSubview(imageView)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered || isPressed else { return }
        NSColor.labelColor.withAlphaComponent(isPressed ? 0.2 : 0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onPress?()
        }
    }
}
