import SwiftUI

/// Пространство имён дизайн-системы Sage.
public enum DesignSystem {
    /// Стандартный размер окна приложения (как в макете 1180×760).
    public static let windowSize = CGSize(width: 1180, height: 760)
}

/// Hover-эффект: подсветка фона при наведении (как `style-hover` в макете).
public struct HoverHighlight: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var hovering = false

    public init(color: Color, radius: CGFloat = Radius.sm) {
        self.color = color
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hovering ? color : .clear)
            )
            .onHover { hovering = $0 }
    }
}

public extension View {
    func hoverHighlight(_ color: Color, radius: CGFloat = Radius.sm) -> some View {
        modifier(HoverHighlight(color: color, radius: radius))
    }
}
