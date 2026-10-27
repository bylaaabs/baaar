import AppKit
import ScreenCaptureKit

/// Pictures of status items, taken while they are visible and kept for when they are hidden.
///
/// macOS 27 draws every status item into one transparent "Menubar" window, so a
/// capture of that window cropped to an item's AX frame is the item on its own.
@MainActor
final class ItemImageCache {
    private var images: [String: NSImage] = [:]
    /// When each picture was taken, to tell a picture older than the app that draws the item now.
    private var takenAt: [String: Date] = [:]
    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "com.laaabs.baaar/items", directoryHint: .isDirectory)
    }

    func image(for item: MenuBarItem) -> NSImage? {
        if let image = images[item.id] { return image }
        let url = fileURL(for: item.id)
        guard let image = NSImage(contentsOf: url) else { return nil }
        // Pictures taken of a hidden menu bar are opaque boxes, not items; drop them so the item is pictured again.
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil), Self.isSolidBox(cgImage) {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        images[item.id] = image
        takenAt[item.id] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return image
    }

    /// Whether the item's picture was taken before its app last launched: an app that relaunches
    /// (an update, most often) may draw a new icon, and a hidden item is never pictured again on its own.
    func isStale(for item: MenuBarItem) -> Bool {
        guard image(for: item) != nil, let taken = takenAt[item.id],
              let launched = NSRunningApplication(processIdentifier: item.pid)?.launchDate else { return false }
        return taken < launched
    }

    /// Whether a menu bar is on screen to picture: in full-screen spaces it hides until the pointer reaches the top.
    static func isMenuBarOnScreen() async -> Bool {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return false }
        return content.windows.contains { $0.title == "Menubar" && $0.isOnScreen && $0.frame.minY >= 0 }
    }

    /// Captures the given items. Only items that are on screen right now come out usable.
    /// Returns false when there was no menu bar on screen to capture from.
    @discardableResult
    func capture(_ items: [MenuBarItem]) async -> Bool {
        guard Permissions.hasScreenRecording, !items.isEmpty else { return false }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return false }
        let bars = content.windows.filter { $0.title == "Menubar" && $0.isOnScreen && $0.frame.minY >= 0 }
        guard !bars.isEmpty else { return false }
        var pictured = false
        for window in bars {
            let inside = items.filter { item in
                guard let frame = item.frame else { return false }
                return window.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
            }
            guard !inside.isEmpty else { continue }
            let scale = Self.backingScale(forTopLeftRect: window.frame)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard let strip = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
            // The window is transparent around every item. A menu bar hidden in a full-screen space can still
            // report its window on screen, and then captures as an opaque strip with nothing on it.
            guard Self.hasTransparency(strip) else {
                Log.write("menu bar capture is opaque; the menu bar isn't showing")
                continue
            }
            pictured = true
            for item in inside {
                guard let frame = item.frame else { continue }
                let crop = CGRect(
                    x: (frame.minX - window.frame.minX) * scale,
                    y: (frame.minY - window.frame.minY) * scale,
                    width: frame.width * scale,
                    height: frame.height * scale
                ).integral
                guard let cropped = strip.cropping(to: crop), let glyph = Self.trimmed(cropped) else { continue }
                let size = NSSize(width: CGFloat(glyph.width) / scale, height: CGFloat(glyph.height) / scale)
                store(NSImage(cgImage: glyph, size: size), cgImage: glyph, for: item.id)
            }
        }
        return pictured
    }

    private func store(_ image: NSImage, cgImage: CGImage, for id: String) {
        images[id] = image
        takenAt[id] = Date()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = image.size // Stored as DPI, so the PNG reloads at point size on Retina.
        try? rep.representation(using: .png, properties: [:])?.write(to: fileURL(for: id))
    }

    private func fileURL(for id: String) -> URL {
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return directory.appending(path: String(safe) + ".png")
    }

    private static func backingScale(forTopLeftRect rect: CGRect) -> CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }?.backingScaleFactor ?? 2
    }

    /// Crops an item capture to its visible pixels, dropping the padding the menu bar adds around it.
    ///
    /// Returns nil when there is nothing to show: a capture taken mid-animation or
    /// of an item that is not on screen is fully transparent, and one of a hidden
    /// menu bar is fully opaque.
    private static func trimmed(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let pixels = rgba(image) else { return nil }

        // Rows in the buffer run top to bottom, matching CGImage.cropping(to:).
        var minX = width, minY = height, maxX = -1, maxY = -1, opaque = 0, clear = 0
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * width + x) * 4 + 3]
                guard alpha > 24 else {
                    clear += 1
                    continue
                }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                if alpha > 160 { opaque += 1 }
            }
        }
        guard maxX >= minX, clear > 0, opaque >= max(4, width * height / 200) else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// Whether any pixel is (nearly) transparent, as the menu bar is around every item.
    private static func hasTransparency(_ image: CGImage) -> Bool {
        guard let pixels = rgba(image) else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] <= 24 }
    }

    /// Whether every pixel is opaque and of one colour: a box, not an item's glyph.
    private static func isSolidBox(_ image: CGImage) -> Bool {
        guard let pixels = rgba(image) else { return false }
        let first = Array(pixels[0..<4])
        return stride(from: 0, to: pixels.count, by: 4).allSatisfy { index in
            pixels[index + 3] > 160 && (0..<3).allSatisfy { abs(Int(pixels[index + $0]) - Int(first[$0])) <= 8 }
        }
    }

    /// The image's pixels as premultiplied RGBA, rows top to bottom; nil when it can't be drawn.
    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
