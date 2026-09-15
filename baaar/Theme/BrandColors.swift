// The laaabs. palette, as terminaaal defines it. Two colors do the work: cyan accent and
// absolute black. Everything else is a white-opacity ladder. Never invent shades.

import AppKit
import SwiftUI

enum BrandColors {
    // MARK: Anchors

    /// Brand cyan, the single accent.
    static let accent = Color(hex: 0x00B5E2)
    /// Hover and pressed cyan.
    static let accentDeep = Color(hex: 0x009EC5)
    /// Destructive actions.
    static let danger = Color(hex: 0xFF453A)
    /// Something that worked: a granted permission.
    static let success = Color(hex: 0x30D158)
    /// Chrome black.
    static let surface = Color(hex: 0x0A0A0A)
    /// Primary text and icons.
    static let on = Color(hex: 0xFFFFFF)

    // MARK: White-opacity ladder

    static let onSecondary = on.opacity(0.55)
    static let onTertiary = on.opacity(0.30)
    static let onDisabled = on.opacity(0.20)
    static let border = on.opacity(0.20)
    static let separator = on.opacity(0.12)
    static let surfaceHover = on.opacity(0.06)
    /// A control on an unknown background: a field, a segmented track.
    static let surfaceField = on.opacity(0.06)
    /// The recessed groove a control sits in.
    static let surfaceTrack = on.opacity(0.04)
    /// A selected row or segment. One rung above hover.
    static let surfaceSelected = on.opacity(0.08)

    // MARK: Tints

    static let accentWash = accent.opacity(0.06)
    static let accentSoft = accent.opacity(0.12)
    static let accentTint = accent.opacity(0.20)
    static let accentStrong = accent.opacity(0.30)
    static let accentOutline = accent.opacity(0.55)

    static let dangerWash = danger.opacity(0.06)
    static let dangerSoft = danger.opacity(0.12)
    static let dangerTint = danger.opacity(0.20)
    static let dangerStrong = danger.opacity(0.30)
    static let dangerOutline = danger.opacity(0.55)

    // MARK: Shadow

    /// Something floating over the content: the bar, a menu.
    static let shadowOverlay = Color.black.opacity(0.35)
    /// Something lifted off its own surface by a hair: a dragged chip.
    static let shadowRaised = Color.black.opacity(0.35)

    // MARK: Solid lines and lifts

    /// `separator` flattened over `surface`, so crossing lines never stack their alpha.
    static let separatorSolid = Color(hex: 0x272727)
    /// `border` flattened over `surface`.
    static let borderSolid = Color(hex: 0x3B3B3B)
    /// Cards, the bar.
    static let surfaceElevated = Color(hex: 0x141414)
    /// Hover and pressed on top of a card.
    static let surfaceHigh = Color(hex: 0x1A1A1A)

    // MARK: AppKit twins

    static let nsAccent = NSColor(displayP3Red: 0x00 / 255, green: 0xB5 / 255, blue: 0xE2 / 255, alpha: 1)
    static let nsSurface = NSColor(srgbRed: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255, alpha: 1)
    static let nsSurfaceElevated = NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
    static let nsSeparatorSolid = NSColor(srgbRed: 0x27 / 255, green: 0x27 / 255, blue: 0x27 / 255, alpha: 1)
    static let nsOn = NSColor.white
    static let nsOnSecondary = NSColor.white.withAlphaComponent(0.55)
    static let nsSurfaceSelected = NSColor.white.withAlphaComponent(0.08)
    static let nsSeparator = NSColor.white.withAlphaComponent(0.12)
    static let nsShadowOverlay = NSColor.black.withAlphaComponent(0.35)
}

extension Color {
    /// Hex literal (RGB) in Display P3, so the cyan and red render as vividly as the brand
    /// intends. Greys, black and white are identical in P3 and sRGB.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.displayP3, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Hairlines
//
// Every line is one physical pixel: `1 / displayScale`. Borders are drawn as a fill ring, not a
// stroke, which renders heavier.

/// A one-pixel horizontal line.
struct BrandHLine: View {
    @Environment(\.displayScale) private var scale
    var color: Color = BrandColors.separatorSolid
    var body: some View { Rectangle().fill(color).frame(height: 1 / scale) }
}

/// A one-pixel vertical line. `height` nil fills the available height.
struct BrandVLine: View {
    @Environment(\.displayScale) private var scale
    var color: Color = BrandColors.separatorSolid
    var height: CGFloat?
    var body: some View { Rectangle().fill(color).frame(width: 1 / scale, height: height) }
}

extension View {
    /// Fills `fill` and draws a one-pixel ring of `ring` around it, for a self-contained surface.
    func brandHairlineBorder(
        cornerRadius radius: CGFloat,
        fill: Color = BrandColors.surface,
        ring: Color = BrandColors.separatorSolid
    ) -> some View {
        modifier(BrandHairlineBorder(radius: radius, fill: fill, ring: ring))
    }
}

private struct BrandHairlineBorder: ViewModifier {
    @Environment(\.displayScale) private var scale
    let radius: CGFloat
    let fill: Color
    let ring: Color

    func body(content: Content) -> some View {
        let width = 1 / scale
        return content
            .background(fill, in: RoundedRectangle(cornerRadius: max(radius - width, 0)))
            .padding(width)
            .background(ring, in: RoundedRectangle(cornerRadius: radius))
    }
}
