import SwiftUI

struct PermissionsPane: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandBlock("permissions") {
                VStack(alignment: .leading, spacing: 16) {
                    PermissionRow(
                        title: "accessibility",
                        badge: "required",
                        message: "lists and opens menu bar items.",
                        systemImage: "accessibility",
                        isGranted: model.hasAccessibility,
                        grant: model.requestAccessibility
                    )
                    BrandHLine()
                    PermissionRow(
                        title: "screen recording",
                        badge: "optional",
                        message: "shows the real icons in the bar; without it baaar shows each tool's own icon. baaar only captures the menu bar and never records video.",
                        systemImage: "rectangle.dashed.badge.record",
                        isGranted: model.hasScreenRecording,
                        grant: model.requestScreenRecording
                    )
                }
                .brandCard()
            }

            Text("macOS does not say when access changes, so this page checks every second while it is open.")
                .font(.brandCaption)
                .foregroundStyle(BrandColors.onTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // System Settings doesn't notify anyone when access changes, so poll while visible.
            while !Task.isCancelled {
                model.refreshPermissions()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let badge: String
    let message: String
    let systemImage: String
    let isGranted: Bool
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isGranted ? BrandColors.accent : BrandColors.onSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.brandBody)
                        .foregroundStyle(BrandColors.on)
                    BrandBadge(text: badge)
                }
                Text(message)
                    .font(.brandCaption)
                    .foregroundStyle(BrandColors.onSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("granted")
                        .font(.brandCaption)
                }
                .foregroundStyle(BrandColors.success)
                .transition(.opacity)
            } else {
                PillButton("grant", action: grant)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isGranted)
        .accessibilityElement(children: .combine)
    }
}
