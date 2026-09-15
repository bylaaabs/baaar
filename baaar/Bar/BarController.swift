import AppKit

/// What the bar shows for one hidden item.
struct BarEntry {
    let item: MenuBarItem
    /// The captured item, or nil to fall back to the app icon.
    let image: NSImage?
}

/// The floating panel under the chevron that lists hidden items as a bar, a list or a grid.
@MainActor
final class BarController {
    var onSelect: ((MenuBarItem) -> Void)?
    var onClose: (() -> Void)?

    private var panel: BarPanel?
    private var monitors: [Any] = []

    /// When the bar last closed. Clicking the chevron first dismisses the bar through
    /// the panel losing key status, so the click must not reopen it straight away.
    private(set) var closedAt = Date.distantPast

    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// The items the open panel lists, to skip rebuilding it when a refresh finds the same ones.
    private(set) var shownItemIDs: [String] = []

    /// - Parameters:
    ///   - anchor: The chevron's frame in AppKit screen coordinates; the bar is centred under it.
    ///   - appearance: The menu bar's appearance. The bar is always drawn dark now, so captured
    ///     icons (white glyphs from a dark menu bar) read as they do there; kept for callers.
    func show(entries: [BarEntry], message: String?, mode: DisplayMode, anchor: CGRect?, screen: NSScreen?, appearance: NSAppearance?) {
        close()
        shownItemIDs = entries.map(\.item.id)
        let anchorScreen = anchor.flatMap { anchor in NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } }
        guard let screen = anchorScreen ?? screen ?? NSScreen.main else { return }

        let views = entries.map { entry in
            let view = BarItemView(entry: entry, showsName: mode == .list, fixedWidth: mode == .grid ? 44 : nil)
            view.onPress = { [weak self] in self?.onSelect?(entry.item) }
            return view
        }
        let content = Self.layout(views, mode: mode)
        if let message {
            let label = NSTextField(labelWithString: message.lowercased())
            label.font = .brandCaption
            label.textColor = BrandColors.nsOnSecondary
            content.addArrangedSubview(label)
            if views.isEmpty {
                content.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            }
        }

        let fitting = content.fittingSize
        let margin: CGFloat = 8
        let width = min(max(fitting.width, 44), screen.frame.width - margin * 2)
        let height = min(max(fitting.height, 30), screen.visibleFrame.height - margin * 2)
        let centerX = anchor?.midX ?? screen.frame.maxX - width / 2 - margin
        let x = min(max(centerX - width / 2, screen.frame.minX + margin), screen.frame.maxX - width - margin)
        let top = min(anchor?.minY ?? screen.visibleFrame.maxY, screen.visibleFrame.maxY) - 6
        let surfaceFrame = NSRect(x: x, y: top - height, width: width, height: height)

        // The panel is larger than the surface by the shadow's reach, so the shadow isn't clipped.
        let insets = BarContainerView.shadowInsets
        let frame = NSRect(
            x: surfaceFrame.minX - insets.left,
            y: surfaceFrame.minY - insets.bottom,
            width: surfaceFrame.width + insets.left + insets.right,
            height: surfaceFrame.height + insets.top + insets.bottom
        )

        let panel = BarPanel(contentRect: frame)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = BarContainerView(content: content)
        panel.onCancel = { [weak self] in self?.close() }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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

    private static func layout(_ views: [BarItemView], mode: DisplayMode) -> NSStackView {
        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        switch mode {
        case .bar, .menuBar:
            content.orientation = .horizontal
            content.spacing = 2
            views.forEach(content.addArrangedSubview)
        case .list:
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 0
            views.forEach(content.addArrangedSubview)
            if let widest = views.map(\.fittingSize.width).max() {
                views.forEach { $0.widthAnchor.constraint(equalToConstant: widest).isActive = true }
            }
        case .grid:
            // As close to square as the count allows: 5 items make a 3 × 2 grid.
            let columns = max(1, Int(Double(views.count).squareRoot().rounded(.up)))
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 4
            for start in stride(from: 0, to: views.count, by: columns) {
                let row = NSStackView(views: Array(views[start..<min(start + columns, views.count)]))
                row.orientation = .horizontal
                row.spacing = 4
                content.addArrangedSubview(row)
            }
        }
        return content
    }

    #if DEBUG
    /// Screen frames (AppKit coordinates) of the item views, to click them from scripts.
    var debugItemFrames: [CGRect] {
        guard let panel, let content = panel.contentView else { return [] }
        return Self.itemViews(in: content).map { panel.convertToScreen($0.convert($0.bounds, to: nil)) }
    }

    private static func itemViews(in view: NSView) -> [BarItemView] {
        view.subviews.flatMap { ($0 as? BarItemView).map { [$0] } ?? itemViews(in: $0) }
    }
    #endif

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        guard let panel else { return }
        self.panel = nil
        panel.onCancel = nil
        panel.orderOut(nil)
        closedAt = Date()
        onClose?()
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
        // The surface draws the brand shadow itself; the system one would follow the panel's
        // transparent margin rather than the rounded surface.
        hasShadow = false
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

/// The panel's content: a transparent margin for the shadow around the brand surface.
private final class BarContainerView: NSView {
    /// How far the overlay shadow (black .35, radius 12, 4 pt down) reaches past the surface. The top
    /// stops at the 6 pt gap under the menu bar, so the panel never covers the chevron.
    static let shadowInsets = NSEdgeInsets(top: 6, left: 18, bottom: 22, right: 18)

    init(content: NSView) {
        super.init(frame: .zero)
        let surface = BarSurfaceView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        surface.addSubview(content)

        let insets = Self.shadowInsets
        let fill = [
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.topAnchor.constraint(equalTo: surface.topAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ]
        // Fill the surface when the content can stretch, stay centred when it can't (the 44 pt minimum).
        fill.forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate(fill + [
            content.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: surface.widthAnchor),
            content.heightAnchor.constraint(lessThanOrEqualTo: surface.heightAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            surface.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// `surfaceElevated`, radius 9, a one-pixel `separatorSolid` ring and the overlay shadow.
private final class BarSurfaceView: NSView {
    private static let cornerRadius: CGFloat = 9

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.backgroundColor = BrandColors.nsSurfaceElevated.cgColor
        layer.cornerRadius = Self.cornerRadius
        layer.borderWidth = 1 / scale
        layer.borderColor = BrandColors.nsSeparatorSolid.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -4)
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }
}

/// One hidden item: an icon cell, or an icon-and-name row in the list.
private final class BarItemView: NSView {
    var onPress: (() -> Void)?

    private static let height: CGFloat = 30
    private static let iconSlot: CGFloat = 22
    private static let horizontalPadding: CGFloat = 7

    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    private var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }

    init(entry: BarEntry, showsName: Bool, fixedWidth: CGFloat?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = showsName ? nil : entry.item.displayName
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(entry.item.displayName)

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        var imageSize: NSSize
        if let image = entry.image {
            imageView.image = image
            let scale = min(1, (Self.height - 10) / max(image.size.height, 1))
            imageSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        } else if let icon = entry.item.appIcon {
            imageView.image = icon
            imageSize = NSSize(width: 18, height: 18)
        } else {
            // Apple's items have no app icon; show their symbol until they're pictured.
            let symbol = NSImage(systemSymbolName: entry.item.systemItem?.symbolName ?? "questionmark.square.dashed", accessibilityDescription: entry.item.displayName)
            imageView.image = symbol?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            imageView.contentTintColor = BrandColors.nsOn
            imageSize = NSSize(width: 18, height: 18)
        }
        if let fixedWidth, imageSize.width > fixedWidth - 8 {
            imageSize = NSSize(width: fixedWidth - 8, height: imageSize.height * (fixedWidth - 8) / imageSize.width)
        }
        addSubview(imageView)

        let iconWidth = max(imageSize.width, Self.iconSlot)
        var constraints = [
            heightAnchor.constraint(equalToConstant: Self.height),
            imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: imageSize.height),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if showsName {
            let label = NSTextField(labelWithString: entry.item.displayName)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .brandBody
            label.textColor = BrandColors.nsOn
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
            constraints += [
                imageView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding + iconWidth / 2),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding * 2 + iconWidth),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding * 2),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            ]
        } else {
            constraints += [
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                widthAnchor.constraint(equalToConstant: fixedWidth ?? iconWidth + Self.horizontalPadding * 2),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered || isPressed else { return }
        // surfaceSelected on hover, one rung up (separator) while pressed.
        (isPressed ? BrandColors.nsSeparator : BrandColors.nsSurfaceSelected).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            isPressed = false
            return
        }
        confirmPress()
    }

    override func accessibilityPerformPress() -> Bool {
        confirmPress()
        return true
    }

    /// Keeps the pressed highlight up for a moment so the click visibly lands before the bar closes.
    private func confirmPress() {
        isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isPressed = false
            self?.onPress?()
        }
    }
}
