import AppKit
import SwiftUI

struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info?["CFBundleVersion"] as? String else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("baaar")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(version)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A lightweight menu bar manager for macOS 27.")
                .padding(.top, 4)
            Spacer()
            Button("Quit baaar") {
                NSApp.terminate(nil)
            }
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}
