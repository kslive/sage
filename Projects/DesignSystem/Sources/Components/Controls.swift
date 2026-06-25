import SwiftUI

public extension View {
    /// Плейсхолдер, цвет которого подчиняется теме (системный placeholder её не подхватывает).
    /// Цвет берётся из палитры окружения — перекрашивается при смене темы автоматически.
    func sagePlaceholder(_ text: String, when show: Bool) -> some View {
        modifier(SagePlaceholderModifier(text: text, show: show))
    }
}

private struct SagePlaceholderModifier: ViewModifier {
    let text: String
    let show: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if show {
                Text(text).foregroundStyle(palette.tx3).allowsHitTesting(false)
            }
        }
    }
}

/// Переключатель (38×22) дизайн-системы.
public struct SageToggle: View {
    @Binding private var isOn: Bool
    @Environment(\.palette) private var palette

    public init(isOn: Binding<Bool>) { _isOn = isOn }

    public var body: some View {
        Capsule()
            .fill(isOn ? palette.ac : palette.bg3)
            .frame(width: 38, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .onTapGesture {
                withAnimation(SageMotion.smooth) { isOn.toggle() }
            }
    }
}

/// Элемент сегмент-контрола.
public struct SegmentItem<Tag: Hashable>: Identifiable {
    public let id = UUID()
    public let tag: Tag
    public let label: String
    public let monospaced: Bool

    public init(tag: Tag, label: String, monospaced: Bool = false) {
        self.tag = tag
        self.label = label
        self.monospaced = monospaced
    }
}

/// Сегмент-контрол (как «Превью/Markdown» и «A/B» в макете).
public struct SageSegmented<Tag: Hashable>: View {
    private let items: [SegmentItem<Tag>]
    @Binding private var selection: Tag
    private let accentSelected: Bool
    @Environment(\.palette) private var palette
    @Namespace private var thumbNS

    public init(_ items: [SegmentItem<Tag>], selection: Binding<Tag>, accentSelected: Bool = false) {
        self.items = items
        _selection = selection
        self.accentSelected = accentSelected
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.tag == selection
                Text(item.label)
                    .font(item.monospaced
                        ? .system(size: 12, weight: .medium, design: .monospaced)
                        : .system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(foreground(selected: selected))
                    .lineLimit(1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 11)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(accentSelected ? palette.ac : palette.bg3)
                                .matchedGeometryEffect(id: "segThumb", in: thumbNS)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(SageMotion.smooth) { selection = item.tag } }
            }
        }
        .padding(2)
        .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1)
        )
    }

    private func foreground(selected: Bool) -> Color {
        if selected { return accentSelected ? palette.onAccent : palette.tx }
        return palette.tx2
    }
}
