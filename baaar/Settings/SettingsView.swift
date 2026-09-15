import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case layout
    case permissions
    case about

    var id: String { rawValue }

    /// The sidebar name, lowercase like the rest of the UI.
    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .layout: "menubar.rectangle"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

/// The selected pane, shared with the window controller so `show(pane:)` can switch it.
@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
}

struct SettingsView: View {
    let model: AppModel
    let reloader: ModelReloader
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            BrandHLine()
            HStack(spacing: 0) {
                sidebar
                BrandVLine()
                ScrollView {
                    detail
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(24)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandColors.surface)
                .id(navigation.pane)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColors.surface)
        .environment(\.colorScheme, .dark)
        .tint(BrandColors.accent)
    }

    /// Level with the traffic lights. Click-through, so dragging it moves the window through the
    /// transparent titlebar behind it.
    private var titleRow: some View {
        HStack(spacing: 6) {
            Wordmark(height: 10)
            Text("- settings")
                .font(.brandBody)
                .foregroundStyle(BrandColors.on)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NSWindow.brandTitleRowHeight)
        .background(BrandColors.surface)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsNavRow(icon: pane.systemImage, title: pane.title, isSelected: navigation.pane == pane) {
                    navigation.pane = pane
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .frame(width: 188, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(BrandColors.surface)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .layout: LayoutPane(model: model, reloader: reloader)
        case .permissions: PermissionsPane(model: model)
        case .about: AboutPane()
        }
    }
}

/// One sidebar row: 30 pt high, radius 7, cyan symbol and white label when selected.
private struct SettingsNavRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? BrandColors.accent : BrandColors.onSecondary)
                Text(title)
                    .font(isSelected ? .brandNavSelected : .brandNav)
                    .foregroundStyle(isSelected ? BrandColors.on : BrandColors.onSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                isSelected ? BrandColors.surfaceSelected : (isHovered ? BrandColors.surfaceField : .clear),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Copy
//
// The shared enums carry title-case names; the settings UI speaks lowercase.

extension MenuBarSection {
    var settingsLabel: String {
        switch self {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "always hidden"
        }
    }
}

extension DisplayMode {
    var settingsLabel: String {
        switch self {
        case .menuBar: "menu bar"
        case .bar: "bar"
        case .list: "list"
        case .grid: "grid"
        }
    }
}

extension ChevronStyle {
    var settingsLabel: String { rawValue }
}
