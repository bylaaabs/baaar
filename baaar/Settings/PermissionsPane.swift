import SwiftUI

struct PermissionsPane: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    badge: "Required",
                    message: "Lists and opens menu bar items.",
                    systemImage: "accessibility",
                    isGranted: model.hasAccessibility,
                    grant: model.requestAccessibility
                )
                PermissionRow(
                    title: "Screen Recording",
                    badge: "Optional",
                    message: "Shows the real icons in the bar; without it baaar uses app icons. baaar only captures the menu bar and never records video.",
                    systemImage: "rectangle.dashed.badge.record",
                    isGranted: model.hasScreenRecording,
                    grant: model.requestScreenRecording
                )
            }
        }
        .formStyle(.grouped)
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
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.fill.tertiary, in: .capsule)
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.green)
                    .help("Granted")
            } else {
                Button("Grant…", action: grant)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
