#!/usr/bin/env swift
// renders the baaar icon from the brand: the icon is the wordmark, dot included, white on laaabs. black
// with the dot in cyan, at 72 % of the width and optically centred (brand/scripts/generate.mjs).
//
//   swift scripts/render-icon.swift
//
// reads brand/generated/baaar/icon/app-icon.svg (the brand submodule) and writes, relative to the
// repository root:
//   design/icon/baaar.icon/Assets/baaar glyph 1500.png  the transparent layer for Icon Composer
//   design/icon/baaar-icon-master.png                       1024 px, the icon on #0A0A0A
// the layer is the same svg without its background, which icon.json fills instead; icon.json scales
// the 1500 px layer by 1024 / 1500 so it fills Icon Composer's 1024 pt canvas.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appending(path: "brand/generated/baaar/icon/app-icon.svg")
guard let svg = try? String(contentsOf: source, encoding: .utf8) else {
    fatalError("can't read \(source.path); run `git submodule update --init brand`")
}

/// The brand's icon with its background rectangle, or without it for the Icon Composer layer.
func icon(withBackground: Bool) -> NSImage {
    let markup = withBackground ? svg : svg.replacingOccurrences(
        of: ##"<rect [^>]*fill="#0a0a0a"[^>]*/>"##, with: "", options: .regularExpression
    )
    guard markup.contains("#00b5e2"), withBackground || !markup.contains("#0a0a0a"),
          let image = NSImage(data: Data(markup.utf8)) else { fatalError("unexpected \(source.path)") }
    return image
}

func render(_ image: NSImage, size: CGFloat) -> Data {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("no bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    return png
}

let iconFolder = root.appending(path: "design/icon/baaar.icon/Assets")
try FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
try render(icon(withBackground: false), size: 1500).write(to: iconFolder.appending(path: "baaar glyph 1500.png"))
try render(icon(withBackground: true), size: 1024).write(to: root.appending(path: "design/icon/baaar-icon-master.png"))
print("wrote design/icon/baaar.icon/Assets/baaar glyph 1500.png and design/icon/baaar-icon-master.png")
