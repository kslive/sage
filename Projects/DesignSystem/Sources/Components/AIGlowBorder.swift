import SwiftUI

/// Подсветка бордера «работающего ИИ» в духе Apple Intelligence. Правильный приём (без Metal):
/// НЕСКОЛЬКО слоёв обводки с РАЗНЫМ blur — внешнее широкое мягкое гало + средний + тонкий чёткий,
/// по которым бежит вращающийся `AngularGradient`. Blur даёт мягкое свечение (а не жёсткий штрих).
/// Источники: livsycode.com, github.com/jacobamobin/AppleIntelligenceGlowEffect.
public struct AIGlowBorder: ViewModifier {
    private let active: Bool
    private let cornerRadius: CGFloat
    @Environment(\.palette) private var palette
    @State private var rotation = 0.0

    public init(active: Bool, cornerRadius: CGFloat) {
        self.active = active
        self.cornerRadius = cornerRadius
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    /// Вращающийся градиент: акцент → яркий блик → акцент → притухший → акцент. Блик тема-зависимый
    /// (в светлой — светлее-акцент, не белый, иначе «дыра»). Крайние стопы равны → нет шва на 0/360.
    private var sweep: AngularGradient {
        let c = palette.ac
        let glint: Color = palette.isDark ? Color(white: 1, opacity: 0.95) : c.opacity(0.45)
        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: c, location: 0.0),
                .init(color: c.opacity(0.6), location: 0.22),
                .init(color: glint, location: 0.5),
                .init(color: c.opacity(0.6), location: 0.78),
                .init(color: c, location: 1.0),
            ]),
            center: .center, angle: .degrees(rotation))
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if active {
                        shape.stroke(sweep, lineWidth: 3.5).blur(radius: 7).opacity(0.65)
                        shape.stroke(sweep, lineWidth: 2).blur(radius: 2)
                        shape.strokeBorder(sweep, lineWidth: 1.1)
                    } else {
                        shape.strokeBorder(palette.ac.opacity(0.5), lineWidth: 1)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: active)
            }
            .onAppear { if active { spin() } }
            .onChange(of: active) { _, on in if on { spin() } }
    }

    private func spin() {
        rotation = 0
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { rotation = 360 }
    }
}

public extension View {
    /// Подсветка бордера работающего ИИ (Apple-Intelligence-стиль) — мягкое гало переливается пока `active`.
    func aiGlowBorder(active: Bool, cornerRadius: CGFloat) -> some View {
        modifier(AIGlowBorder(active: active, cornerRadius: cornerRadius))
    }
}
