#!/usr/bin/env swift
// Renders the baaar app icon glyph: a `<` chevron followed by three dots, drawn in
// terminaaal's rounded stroke-segment style (segments that abut end to end, with the
// rounded corners leaving a small notch at each seam).
//
//   swift scripts/render-icon-glyph.swift
//
// Writes, relative to the repository root:
//   design/icon/baaar.icon/Assets/baaar glyph 1500.png  transparent 1500 px layer for Icon Composer
//   design/icon/baaar-icon-master.png                   1024 px glyph on #0A0A0A
//
// Geometry is laid out on a 1024 pt canvas (Icon Composer's) and scaled per output.
// Icon Composer places a layer image at one point per pixel, so icon.json scales the
// 1500 px layer by 1024 / 1500 (0.68267) to fill the canvas at a higher density.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Parameters (1024 pt canvas)

let canvas: CGFloat = 1024
/// Stroke thickness. terminaaal's glyph uses 18 pt for a 250 pt tall word; baaar has fewer,
/// larger marks and a heavier stroke, so the chevron still reads at 32 px.
let stroke: CGFloat = 26
/// Corner radius of every segment: terminaaal's ratio (6.4 on a 27.6 stroke).
let corner = stroke * 0.233
/// Height of the chevron, tip to tip.
let chevronHeight: CGFloat = 280
/// Each dot's box.
let dotWidth: CGFloat = 154
let dotHeight: CGFloat = 154
/// How far each paren bulges past the ends of the bars.
let parenBulge: CGFloat = stroke * 0.8
let dotGap: CGFloat = 54
let chevronToDots: CGFloat = 84

let cyan = CGColor(srgbRed: 0x00 / 255.0, green: 0xB5 / 255.0, blue: 0xE2 / 255.0, alpha: 1)
let surface = CGColor(srgbRed: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0A / 255.0, alpha: 1)

// MARK: - Shapes

/// A shape given as its core (the final shape shrunk by `corner`); filling the core and stroking
/// it `2 * corner` wide with round joins gives the shape back with every corner rounded.
struct Shape {
    let core: CGPath
}

/// A convex polygon, listed counter-clockwise in a y-up space, with rounded corners.
func polygon(_ points: [CGPoint]) -> Shape {
    let count = points.count
    // Move every edge inward by `corner` and intersect neighbours.
    var lines: [(CGPoint, CGPoint)] = []
    for index in 0..<count {
        let a = points[index], b = points[(index + 1) % count]
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        // Inward normal of a counter-clockwise polygon is (-dy, dx).
        let nx = -dy / length * corner, ny = dx / length * corner
        lines.append((CGPoint(x: a.x + nx, y: a.y + ny), CGPoint(x: b.x + nx, y: b.y + ny)))
    }
    var inset: [CGPoint] = []
    for index in 0..<count {
        let (p1, p2) = lines[(index + count - 1) % count]
        let (p3, p4) = lines[index]
        let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
        let t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / d
        inset.append(CGPoint(x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y)))
    }
    let path = CGMutablePath()
    path.addLines(between: inset)
    path.closeSubpath()
    return Shape(core: path)
}

func rect(_ r: CGRect) -> Shape {
    polygon([
        CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
        CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
    ])
}

/// A paren: the band between two circular arcs, cut by horizontal lines at `bottom` and `top`.
/// `outerX` is the outermost point of the bulge at the vertical middle; `facing` is +1 for `(`
/// (bulging left) and -1 for `)`.
func paren(outerX: CGFloat, bottom: CGFloat, top: CGFloat, bulge: CGFloat, facing: CGFloat) -> Shape {
    let midY = (bottom + top) / 2
    let half = (top - bottom) / 2
    // Outer arc: through (outerX, midY) and the two end points `bulge` further in.
    let outerRadius = (half * half + bulge * bulge) / (2 * bulge)
    let center = CGPoint(x: outerX + facing * outerRadius, y: midY)
    // Inner arc: same sagitta, shifted in by the stroke, so the band keeps an even weight.
    let innerCenter = CGPoint(x: center.x + facing * stroke, y: midY)

    func arcX(_ c: CGPoint, _ radius: CGFloat, _ y: CGFloat) -> CGFloat {
        c.x - facing * (radius * radius - (y - c.y) * (y - c.y)).squareRoot()
    }
    let steps = 96
    let lo = bottom + corner, hi = top - corner
    var outer: [CGPoint] = [], inner: [CGPoint] = []
    for step in 0...steps {
        let y = lo + (hi - lo) * CGFloat(step) / CGFloat(steps)
        outer.append(CGPoint(x: arcX(center, outerRadius - corner, y), y: y))
        inner.append(CGPoint(x: arcX(innerCenter, outerRadius + corner, y), y: y))
    }
    let path = CGMutablePath()
    path.addLines(between: outer + inner.reversed())
    path.closeSubpath()
    return Shape(core: path)
}

// MARK: - Glyph

func glyph() -> [Shape] {
    var shapes: [Shape] = []
    let totalWidth = chevronHeight / 2 + stroke / 2.squareRoot() + chevronToDots + 3 * dotWidth + 2 * dotGap
    let left = (canvas - totalWidth) / 2
    let midY = canvas / 2

    // Chevron `<`: two arms at 45 degrees of two segments each, cut square to the stroke, whose
    // tip segments meet along a horizontal seam (a mitre), like terminaaal's `/` and `\`.
    let run = chevronHeight / 2
    let band = stroke * 2.squareRoot() // horizontal width of a 45 degree band of `stroke` weight
    let armLength = run * 2.squareRoot() // along the outer edge
    let split = (armLength + stroke / 2) / 2 // gives both segments the same length along their centre line
    let diagonal = 1 / 2.squareRoot()
    for sign in [CGFloat(1), -1] {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: left + x, y: midY + sign * y) }
        // A point `distance` along the outer edge, and its partner across the stroke.
        func outer(_ distance: CGFloat) -> CGPoint { point(distance * diagonal, distance * diagonal) }
        func inner(_ distance: CGFloat) -> CGPoint {
            point((distance + stroke) * diagonal, (distance - stroke) * diagonal)
        }
        let pieces = [
            [point(0, 0), point(band, 0), inner(split), outer(split)],
            [outer(split), inner(split), inner(armLength), outer(armLength)],
        ]
        for var points in pieces {
            if sign < 0 { points.reverse() }
            shapes.append(polygon(points))
        }
    }

    // Three dots, each terminaaal's `.`: a bar on top, a bar below and a paren on either side.
    var x = left + run + stroke * diagonal + chevronToDots
    for _ in 0..<3 {
        let bottom = midY - dotHeight / 2, top = midY + dotHeight / 2
        let barInset = parenBulge + stroke
        shapes.append(rect(CGRect(x: x + barInset, y: top - stroke, width: dotWidth - 2 * barInset, height: stroke)))
        shapes.append(rect(CGRect(x: x + barInset, y: bottom, width: dotWidth - 2 * barInset, height: stroke)))
        let parenBottom = bottom + stroke * 0.5, parenTop = top - stroke * 0.5
        shapes.append(paren(outerX: x, bottom: parenBottom, top: parenTop, bulge: parenBulge, facing: 1))
        shapes.append(paren(outerX: x + dotWidth, bottom: parenBottom, top: parenTop, bulge: parenBulge, facing: -1))
        x += dotWidth + dotGap
    }
    return shapes
}

// MARK: - Output

func render(size: Int, background: CGColor?, to path: String) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    if let background {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(cyan)
    context.setStrokeColor(cyan)
    context.setLineWidth(2 * corner)
    context.setLineJoin(.round)
    for shape in glyph() {
        context.addPath(shape.core)
        context.drawPath(using: .fillStroke)
    }
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print("wrote \(path)")
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
try render(size: 1500, background: nil, to: "\(root)/design/icon/baaar.icon/Assets/baaar glyph 1500.png")
try render(size: 1024, background: surface, to: "\(root)/design/icon/baaar-icon-master.png")
