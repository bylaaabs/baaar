#!/usr/bin/env swift
// Renders the DMG window background: the "baaar." wordmark, a caption, a cyan arrow from
// where baaar.app sits to where the Applications alias sits, and the laaabs. tagline.
//
//   swift scripts/render-dmg-background.swift
//
// Writes, relative to the repository root:
//   Resources/dmg-background.png   620 x 420 pt at 2x (1240 x 840 px, 144 dpi)
//
// The layout matches scripts/release/make-dmg.sh: a 620 x 420 window, 128 px icons, baaar.app
// centred at (170, 220) and Applications at (450, 220), measured from the top left corner.
// Finder reads the 144 dpi tag and shows the image at 620 x 420 points on a Retina display.
// Colors come from the design tokens: surface #0A0A0A, accent #00B5E2, the white ladder.
// Re-run only when the layout or the brand changes; the result is committed.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Layout (points, y measured from the top like Finder does)

let width: CGFloat = 620
let height: CGFloat = 420
let scale: CGFloat = 2

let appCentre = CGPoint(x: 170, y: 220)
let applicationsCentre = CGPoint(x: 450, y: 220)
let iconSize: CGFloat = 128

let wordmarkHeight: CGFloat = 28
let wordmarkTop: CGFloat = 58
let captionTop: CGFloat = 104
let footerBottom: CGFloat = 24

let arrowGap: CGFloat = 22 // clear space between an icon's edge and the arrow
let arrowWeight: CGFloat = 3
let arrowHead: CGFloat = 11

// MARK: - Tokens

let surface = CGColor(srgbRed: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0A / 255.0, alpha: 1)
let accent = CGColor(srgbRed: 0x00 / 255.0, green: 0xB5 / 255.0, blue: 0xE2 / 255.0, alpha: 1)
let onSecondary = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
let onTertiary = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30)

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appending(path: "baaar/Resources/Fonts/Outfit-Variable.ttf")
let wordmarkURL = root.appending(path: "baaar/Assets.xcassets/Wordmark.imageset/wordmark.svg")
let outputURL = root.appending(path: "Resources/dmg-background.png")

// MARK: - Font

guard let fontData = try? Data(contentsOf: fontURL),
      let baseDescriptor = CTFontManagerCreateFontDescriptorFromData(fontData as CFData)
else { fatalError("can't read \(fontURL.path)") }

/// Outfit at one of the brand weights (500, 600 or 700).
func outfit(_ size: CGFloat, weight: CGFloat) -> CTFont {
    let wghtTag = 0x7767_6874 // 'wght'
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(
        baseDescriptor, [kCTFontVariationAttribute: [wghtTag: weight]] as CFDictionary
    )
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

// MARK: - Canvas

let pixelWidth = Int(width * scale), pixelHeight = Int(height * scale)
guard let context = CGContext(
    data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("can't create the drawing context") }

context.scaleBy(x: scale, y: scale)
context.setFillColor(surface)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.setAllowsAntialiasing(true)
context.setShouldSmoothFonts(true)

/// Converts a distance from the top edge into the context's bottom-up y.
func fromTop(_ y: CGFloat) -> CGFloat { height - y }

/// Draws `text` centred horizontally, with its baseline `baseline` points below the top edge.
func drawCentred(_ text: String, font: CTFont, color: CGColor, baseline: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
    context.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX, y: fromTop(baseline))
    CTLineDraw(line, context)
}

// MARK: - Wordmark

// AppKit rasterises the committed SVG; the letters are white and the dot is cyan in the file.
guard let wordmark = NSImage(contentsOf: wordmarkURL) else { fatalError("can't read \(wordmarkURL.path)") }
let wordmarkWidth = wordmark.size.width * wordmarkHeight / wordmark.size.height
let wordmarkRect = CGRect(
    x: (width - wordmarkWidth) / 2, y: fromTop(wordmarkTop + wordmarkHeight),
    width: wordmarkWidth, height: wordmarkHeight
)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
wordmark.draw(in: wordmarkRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [
    .interpolation: NSImageInterpolation.high,
])
NSGraphicsContext.restoreGraphicsState()

// MARK: - Caption and footer

drawCentred("drag baaar to Applications", font: outfit(13, weight: 500), color: onSecondary, baseline: captionTop + 13)
drawCentred("a tool by laaabs.", font: outfit(11, weight: 500), color: onTertiary, baseline: height - footerBottom)

// MARK: - Arrow

let arrowY = fromTop(appCentre.y)
let arrowStart = appCentre.x + iconSize / 2 + arrowGap
let arrowEnd = applicationsCentre.x - iconSize / 2 - arrowGap
context.setStrokeColor(accent)
context.setLineWidth(arrowWeight)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: arrowStart, y: arrowY))
context.addLine(to: CGPoint(x: arrowEnd, y: arrowY))
context.strokePath()
context.move(to: CGPoint(x: arrowEnd - arrowHead, y: arrowY + arrowHead))
context.addLine(to: CGPoint(x: arrowEnd, y: arrowY))
context.addLine(to: CGPoint(x: arrowEnd - arrowHead, y: arrowY - arrowHead))
context.strokePath()

// MARK: - Output

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("can't encode the PNG") }
let dpi = 72 * scale
CGImageDestinationAddImage(destination, image, [
    kCGImagePropertyDPIWidth: dpi,
    kCGImagePropertyDPIHeight: dpi,
] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("can't write \(outputURL.path)") }
print("wrote \(outputURL.path) (\(pixelWidth) x \(pixelHeight) px, \(Int(dpi)) dpi)")
