import SwiftUI

struct GeneralPane: View {
    @Bindable var model: AppModel

    /// Where the chevron points while hidden items are tucked away in the selected mode.
    private var restingDirection: ChevronDirection {
        model.displayMode == .menuBar ? .left : .down
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandBlock("show hidden items") {
                HStack(spacing: 10) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        DisplayModeCard(mode: mode, chevronStyle: model.chevronStyle, isSelected: model.displayMode == mode) {
                            model.displayMode = mode
                        }
                    }
                }
            }

            BrandBlock("chevron") {
                VStack(alignment: .leading, spacing: 16) {
                    BrandRow("icon", detail: "points where hidden items appear: sideways in the menu bar, down for the bar, list and grid.") {
                        BrandSegmented(
                            selection: $model.chevronStyle,
                            options: ChevronStyle.allCases.map { style in
                                .init(value: style, label: "", symbol: style.symbolName(restingDirection), help: style.settingsLabel)
                            }
                        )
                    }
                    BrandHLine()
                    BrandRow("new items go to", detail: "where baaar puts menu bar items it has not seen before.") {
                        BrandSegmented(
                            selection: $model.newAppSection,
                            options: MenuBarSection.allCases.map { .init(value: $0, label: $0.settingsLabel) }
                        )
                    }
                }
                .brandCard()
            }

            BrandBlock("behavior") {
                VStack(alignment: .leading, spacing: 16) {
                    BrandRow("hide again automatically", detail: "in menu bar mode, hidden items tuck away when you click elsewhere or after 15 seconds away from the menu bar.") {
                        BrandToggle(isOn: $model.autoRehide, label: "hide again automatically")
                    }
                    BrandHLine()
                    BrandRow("launch at login") {
                        BrandToggle(isOn: $model.launchesAtLogin, label: "launch at login")
                    }
                }
                .brandCard()
            }

            Text("click the chevron to show hidden items. ⌥-click it, or pick show all in its menu, to include always hidden ones. the baaar icon opens this window.")
                .font(.brandCaption)
                .foregroundStyle(BrandColors.onTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DisplayModeCard: View {
    let mode: DisplayMode
    let chevronStyle: ChevronStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                DisplayModePreview(mode: mode, chevronStyle: chevronStyle, isSelected: isSelected)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 7))

                Text(mode.settingsLabel)
                    .font(isSelected ? .brandButton : .brandCallout)
                    .foregroundStyle(isSelected ? BrandColors.on : BrandColors.onSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? BrandColors.accentWash : (isHovered ? BrandColors.surfaceHover : BrandColors.surfaceTrack),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? BrandColors.accent : BrandColors.separator, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(mode.settingsLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature screen: a menu bar strip with item dots, and how hidden items appear in this mode.
private struct DisplayModePreview: View {
    let mode: DisplayMode
    let chevronStyle: ChevronStyle
    let isSelected: Bool

    private let dot: CGFloat = 4

    private var hiddenColor: Color { isSelected ? BrandColors.accent : BrandColors.onSecondary }

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
                .background(BrandColors.surfaceHigh, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(BrandColors.separatorSolid, lineWidth: 0.5))
                .padding(.trailing, 14)
            case .list:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 3) {
                            hiddenDot
                            RoundedRectangle(cornerRadius: 1)
                                .fill(BrandColors.onTertiary)
                                .frame(width: 18, height: 2)
                        }
                    }
                }
                .padding(4)
                .background(BrandColors.surfaceHigh, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(BrandColors.separatorSolid, lineWidth: 0.5))
                .padding(.trailing, 12)
            case .grid:
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(hiddenColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                }
                .padding(4)
                .background(BrandColors.surfaceHigh, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(BrandColors.separatorSolid, lineWidth: 0.5))
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
            Image(systemName: chevronStyle.symbolName(mode == .menuBar ? .left : .down))
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(BrandColors.onSecondary)
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(BrandColors.onTertiary).frame(width: dot, height: dot)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 9)
        .background(BrandColors.surfaceElevated, in: RoundedRectangle(cornerRadius: 2))
    }

    private var hiddenDot: some View {
        Circle().fill(hiddenColor).frame(width: dot, height: dot)
    }
}
