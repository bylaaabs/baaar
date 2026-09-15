import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case layout
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .layout: "Layout"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

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
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The sidebar list wants an optional selection; an empty click keeps the current pane.
    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { navigation.pane },
            set: { if let pane = $0 { navigation.pane = pane } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model)
        case .layout: LayoutPane(model: model)
        case .permissions: PermissionsPane(model: model)
        case .about: AboutPane()
        }
    }
}
