// The controls of the laaabs. look, as terminaaal's settings draw them: a capsule toggle, pill
// buttons, a segmented pick, labelled blocks and rows, badges and links.

import AppKit
import SwiftUI

// MARK: - Layout

/// A labelled group: an onSecondary body label over its content.
struct BrandBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.brandBody)
                .foregroundStyle(BrandColors.onSecondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label, an optional caption under it, and a control on the trailing edge.
struct BrandRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder let control: Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.brandBody)
                    .foregroundStyle(BrandColors.on)
                if let detail {
                    Text(detail)
                        .font(.brandCaption)
                        .foregroundStyle(BrandColors.onSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// A card in a settings list: the recessed track fill, radius 10.
    func brandCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColors.surfaceTrack, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Toggle

/// A capsule switch: cyan when on, the separator rung when off, a white 18 pt knob.
struct BrandToggle: View {
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? BrandColors.accent : BrandColors.separator)
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(label, isOn: $isOn)
        }
    }
}

// MARK: - Buttons

/// How loud a pill button is.
enum PillKind {
    case primary, secondary, destructive
}

/// A pill button: cyan fill, a quiet outline, or a danger outline. Radius 8, padding 8 / 16.
struct PillButton<Leading: View>: View {
    typealias Kind = PillKind

    let title: String
    var kind: Kind = .primary
    let action: () -> Void
    @ViewBuilder let leading: Leading

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, kind: Kind = .primary, action: @escaping () -> Void, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.kind = kind
        self.action = action
        self.leading = leading()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading
                Text(title).font(.brandButton)
            }
        }
        .buttonStyle(PillButtonStyle(kind: kind, isEnabled: isEnabled))
    }
}

extension PillButton where Leading == EmptyView {
    init(_ title: String, kind: Kind = .primary, action: @escaping () -> Void) {
        self.init(title, kind: kind, action: action) { EmptyView() }
    }
}

private struct PillButtonStyle: ButtonStyle {
    let kind: PillKind
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 8)
        return configuration.label
            .foregroundStyle(foreground)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(fill(pressed: pressed), in: shape)
            .overlay(shape.strokeBorder(outline, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: isEnabled ? .white : BrandColors.onSecondary
        case .secondary: isEnabled ? BrandColors.on : BrandColors.onDisabled
        case .destructive: isEnabled ? BrandColors.danger : BrandColors.dangerOutline
        }
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary: isEnabled ? (pressed ? BrandColors.accentDeep : BrandColors.accent) : BrandColors.accentStrong
        case .secondary: pressed ? BrandColors.surfaceSelected : BrandColors.surfaceField
        case .destructive: pressed ? BrandColors.dangerSoft : .clear
        }
    }

    private var outline: Color {
        switch kind {
        case .primary: .clear
        case .secondary: BrandColors.border
        case .destructive: BrandColors.dangerOutline
        }
    }
}

// MARK: - Segmented

/// A pick between a few options on a recessed track. Each option shows a label, a symbol, or both.
struct BrandSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        var label: String
        var symbol: String?
        /// Spoken and shown on hover when only the symbol is visible.
        var help: String?
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(3)
        .background(BrandColors.surfaceTrack, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(BrandColors.separator, lineWidth: 1))
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            withAnimation(.easeOut(duration: 0.12)) { selection = option.value }
        } label: {
            HStack(spacing: 5) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? BrandColors.accent : BrandColors.onSecondary)
                }
                if !option.label.isEmpty {
                    Text(option.label)
                        .font(.brandCallout)
                        .foregroundStyle(isSelected ? BrandColors.on : BrandColors.onSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, option.label.isEmpty ? 8 : 10)
            .frame(minWidth: 30, minHeight: 24)
            .background(isSelected ? BrandColors.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(option.help ?? "")
        .accessibilityLabel(option.help ?? option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Small pieces

/// A small label on a tinted capsule: "required", "optional", "credits".
struct BrandBadge: View {
    let text: String
    var tint: Color = BrandColors.onSecondary

    var body: some View {
        Text(text)
            .font(.brandBadge)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(BrandColors.surfaceSelected, in: Capsule())
    }
}

/// A cyan caption that opens a URL.
struct BrandLink: View {
    let title: String
    let url: String
    var font: Font = .brandCaption
    var color: Color = BrandColors.accent

    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } label: {
            Text(title)
                .font(font)
                .foregroundStyle(color)
                .underline(isHovered, color: color)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(url)
    }
}

/// A notice on a tinted wash: a symbol, a title, a message and an optional action.
struct BrandCallout: View {
    let systemImage: String
    var tint: Color = BrandColors.accent
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.brandBody)
                    .foregroundStyle(BrandColors.on)
                Text(message)
                    .font(.brandCaption)
                    .foregroundStyle(BrandColors.onSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                PillButton(actionTitle, action: action)
            }
        }
        .padding(12)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.20), lineWidth: 1))
    }
}
