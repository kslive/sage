import SwiftUI

/// Бейдж-«Рекомендуем» (акцентная pill).
public struct SageBadge: View {
    private let text: String
    @Environment(\.palette) private var palette

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.ac)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(palette.acs, in: Capsule())
    }
}

/// Светящаяся точка статуса «активна».
public struct StatusDot: View {
    private let size: CGFloat
    private let color: Color?
    @Environment(\.palette) private var palette

    public init(size: CGFloat = 7, color: Color? = nil) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        let c = color ?? palette.ac
        Circle()
            .fill(c)
            .frame(width: size, height: size)
            .shadow(color: c, radius: 4)
    }
}
