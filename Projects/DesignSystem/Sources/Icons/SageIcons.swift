import SwiftUI

/// Фирменные иконки Sage (точные SVG-пути из макета).
public enum SageIcons {
    /// Логотип-искра (4-конечная «sparkle» с тонкими лучами).
    public static let sparkLogo =
        "M12 1.6c.2 4.6 1.3 6.9 3.6 8.2c1.6.9 3.6 1.4 6.8 2.2c-3.2.8-5.2 1.3-6.8 2.2"
            + "c-2.3 1.3-3.4 3.6-3.6 8.2c-.2-4.6-1.3-6.9-3.6-8.2c-1.6-.9-3.6-1.4-6.8-2.2"
            + "c3.2-.8 5.2-1.3 6.8-2.2C10.7 8.5 11.8 6.2 12 1.6Z"

    /// Искра для кнопок/ИИ (чуть полнее).
    public static let spark =
        "M12 2c.2 4 1.1 6 3.1 7.1c1.4.8 3.1 1.2 5.9 1.9c-2.8.7-4.5 1.1-5.9 1.9"
            + "C13.1 14 12.2 16 12 20c-.2-4-1.1-6-3.1-7.1c-1.4-.8-3.1-1.2-5.9-1.9"
            + "c2.8-.7 4.5-1.1 5.9-1.9C10.9 8 11.8 6 12 2Z"

    /// GitHub-октокат (viewBox 16×16, заливка).
    public static let githubMark =
        "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49"
            + "-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82"
            + ".72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15"
            + "-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82"
            + ".44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2"
            + " 0 .21.15.46.55.38L16 8c0-4.42-3.58-8-8-8z"

    /// Зубчатый контур шестерёнки (viewBox 16×16, обводка). Центр — отдельным кружком.
    public static let gearCog =
        "M13.3 8c0-.4 0-.7-.1-1l1.3-1-1.5-2.6-1.6.6c-.5-.4-1-.7-1.6-.9L9.5 1.5h-3l-.3 1.6"
            + "c-.6.2-1.1.5-1.6.9l-1.6-.6L1 6l1.3 1c-.1.3-.1.6-.1 1s0 .7.1 1L1 11l1.5 2.6 1.6-.6"
            + "c.5.4 1 .7 1.6.9l.3 1.6h3l.3-1.6c.6-.2 1.1-.5 1.6-.9l1.6.6L15 11l-1.3-1c.1-.3.1-.6.1-1z"
}

/// Иконка-шестерёнка строго по макету (зубчатый контур + центральный кружок).
public struct GearIcon: View {
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 15, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        ZStack {
            SVGShape(SageIcons.gearCog, viewBox: CGSize(width: 16, height: 16))
                .stroke(color, style: StrokeStyle(lineWidth: size * 1.1 / 16, lineJoin: .round))
            Circle().fill(color).frame(width: size * 0.25, height: size * 0.25)
        }
        .frame(width: size, height: size)
    }
}

/// View-обёртка для фирменной искры-логотипа.
public struct SparkLogo: View {
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 24, color: Color = Color(hex: "#4CC38A")) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        SVGShape(SageIcons.sparkLogo)
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Искра для кнопок «Спросить Sage ✦».
public struct SparkMark: View {
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 16, color: Color) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        SVGShape(SageIcons.spark)
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Иконка приложения (squircle с градиентом и искрой) — для онбординга/About/трея.
public struct AppMark: View {
    let size: CGFloat
    public init(size: CGFloat = 74) { self.size = size }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#16201B"), Color(hex: "#0C0E0F")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .overlay(SparkLogo(size: size * 0.54, color: Color(hex: "#4CC38A")))
            .frame(width: size, height: size)
    }
}
