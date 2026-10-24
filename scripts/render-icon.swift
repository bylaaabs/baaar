#!/usr/bin/env swift
// renders the baaar icon glyph from the wordmark: the icon is the wordmark (brand, 2026-09-19),
// white on laaabs. black, centred at 72 % of the width (brand sheet 02), no dot.
//
//   swift scripts/render-icon.swift
//
// reads design/icon/baaar-glyph.svg, the mark without its dot (written by
// brand/scripts/render-wordmark.swift) and writes, relative to the repository root:
//   design/icon/baaar.icon/Assets/baaar glyph 1500.png  the transparent layer for Icon Composer
//   design/icon/baaar-icon-master.png                       1024 px, the glyph on #0A0A0A
// icon.json scales the 1500 px layer by 1024 / 1500 so it fills Icon Composer's 1024 pt canvas.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let svg = root.appending(path: "design/icon/baaar-glyph.svg")
guard let wordmark = NSImage(contentsOf: svg) else { fatalError("can't read \(svg.path)") }

/// the wordmark's width as a share of the canvas.
let widthShare: CGFloat = 0.72

func render(size: CGFloat, background: NSColor?) -> Data {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("no bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let background {
        background.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
    }
    let width = size * widthShare
    let height = width * wordmark.size.height / wordmark.size.width
    let rect = NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
    // tint the (white) vector to white explicitly, so a template asset draws the same.
    let tinted = NSImage(size: wordmark.size, flipped: false) { bounds in
        wordmark.draw(in: bounds)
        NSColor.white.set()
        bounds.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    return png
}

let iconFolder = root.appending(path: "design/icon/baaar.icon/Assets")
try FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
try render(size: 1500, background: nil).write(to: iconFolder.appending(path: "baaar glyph 1500.png"))
try render(size: 1024, background: NSColor(srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255, alpha: 1))
    .write(to: root.appending(path: "design/icon/baaar-icon-master.png"))
print("wrote design/icon/baaar.icon/Assets/baaar glyph 1500.png and design/icon/baaar-icon-master.png")
