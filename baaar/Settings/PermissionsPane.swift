import SwiftUI

struct PermissionsPane: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandBlock(String(localized: "permissions")) {
                VStack(alignment: .leading, spacing: 16) {
                    PermissionRow(
                        title: String(localized: "accessibility"),
                        badge: String(localized: "required"),
                        message: String(localized: "lists and opens menu bar items."),
                        systemImage: "accessibility",
                        isGranted: model.hasAccessibility,
                        grant: model.requestAccessibility
                    )
                    BrandHLine()
                    PermissionRow(
                        title: String(localized: "screen recording"),
                        badge: String(localized: "optional"),
                        message: String(localized: "shows the real icons in the bar; without it baaar shows each tool's own icon. baaar only captures the menu bar and never records video."),
                        systemImage: "rectangle.dashed.badge.record",
                        isGranted: model.hasScreenRecording,
                        grant: model.requestScreenRecording
                    )
                    BrandHLine()
                    PermissionRow(
                        title: String(localized: "menu bar layout"),
                        badge: String(localized: "optional"),
                        message: String(localized: "lets baaar reorder items by editing macos's layout file, without moving your cursor."),
                        systemImage: "arrow.left.arrow.right",
                        isGranted: model.hasLayoutAccess,
                        grantTitle: String(localized: "grant…")
                    ) {
                        model.requestLayoutAccess()
                        // refreshPermissions doesn't cover the layout file; read it back.
                        Task { await model.reload() }
                    }
                }
                .brandCard()
            }

            Text("macos does not say when access changes, so this page checks every second while it is open.")
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
    var grantTitle = String(localized: "grant")
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
                PillButton(grantTitle, action: grant)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isGranted)
        .accessibilityElement(children: .combine)
    }
}
