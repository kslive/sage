import SwiftUI

/// Кривые анимаций из дизайн-системы.
public enum SageMotion {
    public static let pop = Animation.spring(response: 0.32, dampingFraction: 0.78)
    public static let fade = Animation.easeOut(duration: 0.25)
    public static let quick = Animation.easeOut(duration: 0.14)
    public static let smooth = Animation.easeInOut(duration: 0.2)
}

// MARK: - Shimmer (скелетоны)

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    let palette: ThemePalette

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [.clear, palette.tx.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width * 0.6)
                    .offset(x: phase * width * 1.6)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    /// Анимация мерцания для скелетон-плейсхолдеров.
    func shimmer(_ palette: ThemePalette) -> some View {
        modifier(ShimmerModifier(palette: palette))
    }
}
