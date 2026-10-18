import AppKit

/// How the bar, list and grid are painted for each `BarColor`.
struct BarPalette {
    let background: NSColor
    let ring: NSColor
    let foreground: NSColor
    let secondary: NSColor
    let hover: NSColor
    let pressed: NSColor

    init(_ color: BarColor) {
        switch color {
        case .black:
            background = BrandColors.nsSurface
            ring = BrandColors.nsSeparatorSolid
            foreground = BrandColors.nsOn
        case .graphite:
            background = BrandColors.nsSurfaceHigh
            ring = BrandColors.nsBorderSolid
            foreground = BrandColors.nsOn
        case .cyan:
            background = BrandColors.nsAccent
            ring = BrandColors.nsAccentDeep
            foreground = BrandColors.nsOn
        case .white:
            background = NSColor.white
            ring = NSColor.black.withAlphaComponent(0.12)
            foreground = BrandColors.nsSurface
        case .glass:
            // The glass draws itself; these only colour the content on top of it.
            background = .clear
            ring = .clear
            foreground = BrandColors.nsOn
        }
        secondary = foreground.withAlphaComponent(0.55)
        hover = foreground.withAlphaComponent(0.08)
        pressed = foreground.withAlphaComponent(0.16)
    }
}
