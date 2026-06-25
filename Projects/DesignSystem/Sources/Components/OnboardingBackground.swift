import SwiftUI

/// Фон онбординга по макету: мягкое верхнее свечение (`obTop`) + плавающий акцентный блоб.
public struct OnboardingBackground: View {
    @Environment(\.palette) private var palette
    @State private var animate = false

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.bg

                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.obTop, location: 0),
                        .init(color: palette.bg, location: 0.55),
                    ]),
                    center: UnitPoint(x: 0.5, y: -0.1),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 1.1
                )

                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [palette.acs, .clear]),
                            center: .center, startRadius: 0, endRadius: 280
                        )
                    )
                    .frame(width: 560, height: 560)
                    .blur(radius: 30)
                    .offset(
                        x: animate ? geo.size.width * 0.12 : -geo.size.width * 0.10,
                        y: animate ? -geo.size.height * 0.06 : geo.size.height * 0.12
                    )
                    .scaleEffect(animate ? 1.12 : 0.9)
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
        }
        .ignoresSafeArea()
    }
}
