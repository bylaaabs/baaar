// Window chrome for the laaabs. look: dark appearance, brand-black background and a transparent
// titlebar, so the content draws its own title row with the traffic lights floating on top.

import AppKit

extension NSWindow {
    /// Height of the title row the content draws under the transparent titlebar.
    static let brandTitleRowHeight: CGFloat = 32

    /// Applies the brand chrome: black, dark, transparent titlebar over a full-size content view.
    func applyBrandChrome(titleVisible: Bool = false, fullSizeContent: Bool = true) {
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = BrandColors.nsSurface
        isOpaque = true
        titlebarAppearsTransparent = true
        titleVisibility = titleVisible ? .visible : .hidden
        isMovableByWindowBackground = false
        if fullSizeContent { styleMask.insert(.fullSizeContentView) }
        isRestorable = false
    }
}
