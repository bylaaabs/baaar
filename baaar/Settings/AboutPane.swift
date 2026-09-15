import AppKit
import SwiftUI

struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let build = info?["CFBundleVersion"] as? String else { return "version \(short)" }
        return "version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 16)

            Wordmark(height: 28)
            Text(version)
                .font(.brandCaption)
                .foregroundStyle(BrandColors.onSecondary)
                .textSelection(.enabled)

            VStack(spacing: 8) {
                BrandLink(title: "github.com/bylaaabs/baaar", url: "https://github.com/bylaaabs/baaar")
                Spacer(minLength: 0).frame(height: 8)
                BrandLink(title: "hello@laaabs.com", url: "mailto:hello@laaabs.com")
                BrandLink(title: "laaabs.com", url: "https://laaabs.com")
                Spacer(minLength: 0).frame(height: 8)
                BrandLink(title: "aaangelmartin.com", url: "https://aaangelmartin.com")
            }
            .padding(.top, 6)

            Spacer(minLength: 16)

            BrandBadge(text: "credits", tint: BrandColors.onTertiary)
            Text("built on macOS 27's menubaragent visibility restriction.")
                .font(.brandCaption)
                .foregroundStyle(BrandColors.onSecondary)
                .multilineTextAlignment(.center)

            BrandLink(title: "a tool by laaabs.", url: "https://laaabs.com", color: BrandColors.onTertiary)
                .padding(.top, 6)

            PillButton("quit baaar", kind: .destructive) {
                NSApp.terminate(nil)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}
