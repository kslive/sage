import SwiftUI

public enum SageButtonKind {
    case primary
    case secondary
    case ghost
}

/// Кнопка дизайн-системы (primary / secondary / ghost).
public struct SageButton: View {
    private let title: String
    private let kind: SageButtonKind
    private let icon: String?
    private let fullWidth: Bool
    private let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    public init(
        _ title: String,
        kind: SageButtonKind = .primary,
        icon: String? = nil,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.icon = icon
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .sageType(.uiMedium)
            .foregroundStyle(foreground)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: palette.onAccent
        case .secondary: palette.tx
        case .ghost: palette.tx2
        }
    }

    private var background: Color {
        switch kind {
        case .primary: palette.ac.opacity(hovering ? 0.92 : 1)
        case .secondary: hovering ? palette.bgh : .clear
        case .ghost: hovering ? palette.bgh : .clear
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .secondary: palette.bd
        case .ghost: .clear
        }
    }
}

/// Pill «Спросить Sage ✦ ⌘J».
public struct AskSagePill: View {
    private let title: String
    private let shortcut: String?
    private let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    public init(_ title: String, shortcut: String? = "⌘J", action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                SparkMark(size: 14, color: palette.ac)
                Text(title).sageType(.uiMedium).foregroundStyle(palette.tx)
                    .fixedSize(horizontal: true, vertical: false)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.tx3)
                        .padding(.horizontal, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(palette.bd, lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(palette.bg2)
            .overlay { shimmerBorder }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var shimmerBorder: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
            let angle = (ctx.date.timeIntervalSinceReferenceDate / 4.5).truncatingRemainder(dividingBy: 1) * 360
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [palette.bd2, palette.ac.opacity(hovering ? 0.95 : 0.6), palette.bd2, palette.bd2]),
                        center: .center, angle: .degrees(angle)
                    ),
                    lineWidth: 1.2
                )
        }
    }
}
