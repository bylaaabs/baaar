import SwiftUI

struct GeneralPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Show hidden items") {
                HStack(spacing: 12) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        DisplayModeCard(mode: mode, isSelected: model.displayMode == mode) {
                            model.displayMode = mode
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: $model.autoRehide) {
                    Text("Hide items again automatically")
                    Text("In the menu bar mode, hidden items tuck away when you click elsewhere or after 15 seconds away from the menu bar.")
                }
                Toggle("Launch at login", isOn: $model.launchesAtLogin)
            } footer: {
                Text("Click the ‹ chevron in the menu bar to show hidden items, or ⌥-click it to include always-hidden ones. The baaar icon opens these settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplayModeCard: View {
    let mode: DisplayMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                DisplayModePreview(mode: mode)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 6))

                Text(mode.title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.background, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature screen: a menu bar strip with item dots, and how hidden items appear in this mode.
private struct DisplayModePreview: View {
    let mode: DisplayMode

    private let dot: CGFloat = 4

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            strip
            switch mode {
            case .menuBar:
                EmptyView()
            case .bar:
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in hiddenDot }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.fill.secondary, in: .capsule)
                .padding(.trailing, 14)
            case .list:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 3) {
                            hiddenDot
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.secondary)
                                .frame(width: 18, height: 2)
                        }
                    }
                }
                .padding(4)
                .background(.fill.secondary, in: .rect(cornerRadius: 3))
                .padding(.trailing, 12)
            case .grid:
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(.tint)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                }
                .padding(4)
                .background(.fill.secondary, in: .rect(cornerRadius: 3))
                .padding(.trailing, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .accessibilityHidden(true)
    }

    private var strip: some View {
        HStack(spacing: 3) {
            Spacer(minLength: 0)
            if mode == .menuBar {
                ForEach(0..<3, id: \.self) { _ in hiddenDot }
            }
            Image(systemName: "chevron.left")
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(.secondary).frame(width: dot, height: dot)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 9)
        .background(.fill.tertiary, in: .rect(cornerRadius: 2))
    }

    private var hiddenDot: some View {
        Circle().fill(.tint).frame(width: dot, height: dot)
    }
}
