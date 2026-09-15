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
        directory = caches.appending(path: "com.aaangelmartin.baaar/items", directoryHint: .isDirectory)
    }

    func image(for item: MenuBarItem) -> NSImage? {
        if let image = images[item.id] { return image }
        guard let image = NSImage(contentsOf: fileURL(for: item.id)) else { return nil }
        images[item.id] = image
        return image
    }

    /// Captures the given items. Only items that are on screen right now come out usable.
    func capture(_ items: [MenuBarItem]) async {
        guard Permissions.hasScreenRecording, !items.isEmpty else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
        for window in content.windows where window.title == "Menubar" && window.isOnScreen {
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
                guard let cropped = strip.cropping(to: crop), Self.hasVisiblePixels(cropped) else { continue }
                store(NSImage(cgImage: cropped, size: frame.size), cgImage: cropped, for: item.id)
            }
        }
    }

    private func store(_ image: NSImage, cgImage: CGImage, for id: String) {
        images[id] = image
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])?.write(to: fileURL(for: id))
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

    /// A capture taken mid-animation or of an overflowed item is fully transparent.
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        let opaque = stride(from: 3, to: pixels.count, by: 4).reduce(0) { $0 + (pixels[$1] > 160 ? 1 : 0) }
        return opaque >= max(4, width * height / 200)
    }
}
