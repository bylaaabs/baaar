import AppKit
import SwiftUI

/// The `baaar.` wordmark. Uses the vector `Wordmark` asset when the bundle has one, and otherwise
/// sets the word in Outfit 700 with a cyan dot. `height` is the height of the letters.
struct Wordmark: View {
    var height: CGFloat = 28
    var tint: Color = BrandColors.on

    /// Outfit's ascender ("b") is 0.70 em tall, so this font size makes the letters `height` tall.
    private var fontSize: CGFloat { (height / 0.70).rounded(.toNearestOrEven) }

    var body: some View {
        Group {
            if let asset = NSImage(named: "Wordmark") {
                if asset.isTemplate {
                    Image(nsImage: asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(nsImage: asset)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Text("baaar\(Text(".").foregroundStyle(BrandColors.accent))")
                    .font(.outfit(fontSize, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("baaar")
    }
}
