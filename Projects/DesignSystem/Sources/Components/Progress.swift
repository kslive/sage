import SwiftUI

/// Кольцевой прогресс с процентом по центру (онбординг-загрузка).
public struct CircularProgress: View {
    private let fraction: Double
    private let diameter: CGFloat
    private let lineWidth: CGFloat
    private let showError: Bool
    @Environment(\.palette) private var palette

    public init(fraction: Double, diameter: CGFloat = 118, lineWidth: CGFloat = 6, showError: Bool = false) {
        self.fraction = fraction
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showError = showError
    }

    public var body: some View {
        ZStack {
            Circle().stroke(palette.bd, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(palette.ac, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(SageMotion.fade, value: fraction)
            if showError {
                Text("⚠️").font(.system(size: diameter * 0.25))
            } else {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: diameter * 0.2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.tx)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Линейный прогресс-бар.
public struct LinearProgress: View {
    private let fraction: Double
    private let height: CGFloat
    @Environment(\.palette) private var palette

    public init(fraction: Double, height: CGFloat = 5) {
        self.fraction = fraction
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bg3)
                Capsule().fill(palette.ac)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: height)
        .animation(SageMotion.fade, value: fraction)
    }
}

/// Скелетон-плейсхолдер с мерцанием.
public struct SkeletonBar: View {
    private let width: CGFloat?
    private let height: CGFloat
    private let animated: Bool
    @Environment(\.palette) private var palette

    public init(width: CGFloat? = nil, height: CGFloat = 11, animated: Bool = true) {
        self.width = width
        self.height = height
        self.animated = animated
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(palette.bg3)
            .frame(width: width, height: height)
            .modifier(ConditionalShimmer(animated: animated, palette: palette))
    }
}

private struct ConditionalShimmer: ViewModifier {
    let animated: Bool
    let palette: ThemePalette
    func body(content: Content) -> some View {
        if animated { content.shimmer(palette) } else { content }
    }
}

/// Маленький крутящийся индикатор (загрузка).
public struct SageSpinner: View {
    private let size: CGFloat
    private let color: Color?
    @Environment(\.palette) private var palette
    @State private var spin = false

    public init(size: CGFloat = 16, color: Color? = nil) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Circle()
            .trim(from: 0, to: 0.4)
            .stroke(color ?? palette.ac, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            }
            .onDisappear { spin = false }
    }
}

/// Искра в кружке (фон `acs`) с расходящимся кольцом — «ответ ИИ готов (непрочитан)».
/// Точная реплика `@keyframes rglow` макета: кольцо `ac` расширяется (scale 1→1.6) и гаснет
/// (opacity .55→0), цикл 1.8s. corner = size/2 → круг (бейдж строки); меньший corner → скруг-квадрат (тост).
public struct GlowRing: View {
    private let size: CGFloat
    private let sparkSize: CGFloat
    private let corner: CGFloat
    @Environment(\.palette) private var palette
    @State private var on = false

    public init(size: CGFloat = 15, sparkSize: CGFloat = 9, corner: CGFloat? = nil) {
        self.size = size
        self.sparkSize = sparkSize
        self.corner = corner ?? size / 2
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(palette.ac, lineWidth: 1.5)
                .frame(width: size, height: size)
                .scaleEffect(on ? 1.6 : 1.0)
                .opacity(on ? 0 : 0.55)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(palette.acs)
                .frame(width: size, height: size)
            SparkMark(size: sparkSize, color: palette.ac)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
        }
        .onDisappear { on = false }
    }
}

/// Анимация «печатает…» (три точки).
public struct TypingDots: View {
    private let color: Color?
    @Environment(\.palette) private var palette
    @State private var phase = 0

    public init(color: Color? = nil) { self.color = color }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle()
                    .fill(color ?? palette.tx3)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.25)
                    .offset(y: phase == i ? -3 : 0)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
            }
        }
    }
}
