import AppKit
import ScreenCaptureKit

/// Pictures of status items, taken while they are visible and kept for when they are hidden.
///
/// macOS 27 draws every status item into one transparent "Menubar" window, so a
/// capture of that window cropped to an item's AX frame is the item on its own.
@MainActor
final class ItemImageCache {
    private var images: [String: NSImage] = [:]
    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "com.laaabs.baaar/items", directoryHint: .isDirectory)
    }

    func image(for item: MenuBarItem) -> NSImage? {
        if let image = images[item.id] { return image }
        guard let image = NSImage(contentsOf: fileURL(for: item.id)) else { return nil }
        images[item.id] = image
        return image
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
        return true
    }

    private func store(_ image: NSImage, cgImage: CGImage, for id: String) {
        images[id] = image
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
    /// of an item that is not on screen is fully transparent.
    private static func trimmed(_ image: CGImage) -> CGImage? {
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
        guard drawn else { return nil }

        // Rows in the buffer run top to bottom, matching CGImage.cropping(to:).
        var minX = width, minY = height, maxX = -1, maxY = -1, opaque = 0
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                if pixels[(y * width + x) * 4 + 3] > 160 { opaque += 1 }
            }
        }
        guard maxX >= minX, opaque >= max(4, width * height / 200) else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
