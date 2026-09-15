#!/usr/bin/env swift
// Renders the "baaar." wordmark as a vector SVG from Outfit's glyph outlines (weight 700),
// set tight like terminaaal's wordmark: letters close up until they touch, and where a
// round side meets its neighbour the earlier letter is carved back to leave an even gap.
//
//   swift scripts/render-wordmark.swift [path/to/Outfit-Variable.ttf] [preview.png]
//
// Writes baaar/Assets.xcassets/Wordmark.imageset/wordmark.svg (letters white, the dot
// #00B5E2). The asset renders as a template, so views tint it as one colour; drawn with
// `.renderingMode(.original)` the dot keeps its cyan. Needs macOS 14 for CGPath booleans.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontPath = arguments.count > 1
    ? arguments[1]
    : root.appending(path: "baaar/Resources/Fonts/Outfit-Variable.ttf").path
let previewPath = arguments.count > 2 ? arguments[2] : nil

let text = "baaar."
let weight: CGFloat = 700
let size: CGFloat = 2000
/// The gap left where letters meet, as a share of the x-height (terminaaal: 100 on a ~1000 x-height).
let gapRatio: CGFloat = 0.1
let white = "#FFFFFF"
let cyan = "#00B5E2"

// MARK: - Font

guard let data = try? Data(contentsOf: URL(fileURLWithPath: fontPath)),
      let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
else { fatalError("can't read \(fontPath)") }
let wghtTag = 0x7767_6874 // 'wght'
let variation = CTFontDescriptorCreateCopyWithAttributes(
    descriptor, [kCTFontVariationAttribute: [wghtTag: weight]] as CFDictionary
)
let font = CTFontCreateWithFontDescriptor(variation, size, nil)
let xHeight = CTFontGetXHeight(font)
let gap = xHeight * gapRatio

// MARK: - Outlines

struct Letter {
    var path: CGPath
    let isDot: Bool
}

var characters = Array(text.utf16)
var glyphs = [CGGlyph](repeating: 0, count: characters.count)
guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { fatalError("missing glyphs") }

var letters: [Letter] = []
var penX: CGFloat = 0
for (index, glyph) in glyphs.enumerated() {
    guard let outline = CTFontCreatePathForGlyph(font, glyph, nil)?.normalized(using: .winding) else { continue }
    let character = Character(UnicodeScalar(characters[index])!)
    let bounds = outline.boundingBoxOfPath
    // A straight stem (b, r) or the dot keeps a gap; a bowl (a) closes up until it touches, then carves.
    let straightLeft = character == "b" || character == "r"
    if let previous = letters.last {
        // The previous letter's right edge within this letter's height, so the dot tucks under the r's arm.
        let band = CGPath(rect: CGRect(x: -1e6, y: bounds.minY, width: 2e6, height: bounds.height), transform: nil)
        let previousRight = previous.path.intersection(band).boundingBoxOfPath.maxX
        penX = previousRight + (straightLeft || character == "." ? gap : 0) - bounds.minX
    } else {
        penX = -bounds.minX
    }
    var transform = CGAffineTransform(translationX: penX, y: 0)
    let placed = outline.copy(using: &transform)!
    letters.append(Letter(path: placed, isDot: character == "."))
}

// Carve each letter back from the one after it, so touching shapes keep an even gap.
for index in letters.indices.dropLast() {
    let next = letters[index + 1].path
    let halo = next.union(next.copy(strokingWithWidth: gap * 2, lineCap: .round, lineJoin: .round, miterLimit: 10))
    letters[index].path = letters[index].path.subtracting(halo)
}

// MARK: - SVG

let bounds = letters.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
let width = bounds.width, height = bounds.height

func number(_ value: CGFloat) -> String {
    let rounded = (value * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", rounded)
}

/// SVG path data, moved to the origin with y pointing down.
func svgData(_ path: CGPath) -> String {
    var parts: [String] = []
    func point(_ p: CGPoint) -> String { "\(number(p.x - bounds.minX)) \(number(bounds.maxY - p.y))" }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: parts.append("M\(point(points[0]))")
        case .addLineToPoint: parts.append("L\(point(points[0]))")
        case .addQuadCurveToPoint: parts.append("Q\(point(points[0])) \(point(points[1]))")
        case .addCurveToPoint: parts.append("C\(point(points[0])) \(point(points[1])) \(point(points[2]))")
        case .closeSubpath: parts.append("Z")
        @unknown default: break
        }
    }
    return parts.joined()
}

var svg = "<svg width=\"\(number(width))\" height=\"\(number(height))\" viewBox=\"0 0 \(number(width)) \(number(height))\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">\n"
for letter in letters {
    svg += "<path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"\(svgData(letter.path))\" fill=\"\(letter.isDot ? cyan : white)\"/>\n"
}
svg += "</svg>\n"

let output = root.appending(path: "baaar/Assets.xcassets/Wordmark.imageset/wordmark.svg")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try svg.write(to: output, atomically: true, encoding: .utf8)
print("wrote \(output.path) (\(number(width)) x \(number(height)))")

// MARK: - Preview

if let previewPath {
    let scale: CGFloat = 0.2, margin: CGFloat = 40
    let pixelWidth = Int(width * scale + margin * 2), pixelHeight = Int(height * scale + margin * 2)
    let context = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: 0.04, green: 0.04, blue: 0.04, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    context.translateBy(x: margin, y: margin)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    for letter in letters {
        context.setFillColor(letter.isDot
            ? CGColor(srgbRed: 0, green: 0xB5 / 255.0, blue: 0xE2 / 255.0, alpha: 1)
            : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(letter.path)
        context.fillPath(using: .evenOdd)
    }
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: previewPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(previewPath)")
}
