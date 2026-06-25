import SwiftUI

/// Шкала отступов (4-base) из дизайн-системы.
public enum Spacing {
    public static let xs2: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xl2: CGFloat = 32
    public static let xl3: CGFloat = 40
    public static let xl4: CGFloat = 48
}

/// Радиусы скругления.
public enum Radius {
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 9
    public static let lg: CGFloat = 11
    public static let xl: CGFloat = 14
    public static let pill: CGFloat = 22
    public static let round: CGFloat = 999
}

public extension View {
    /// Тень дизайн-системы (уровень поповеров/меню).
    func sageElevation(_ palette: ThemePalette) -> some View {
        shadow(color: palette.shadow, radius: palette.shadowRadius, x: 0, y: palette.shadowY)
    }

    /// Низкая тень (карточки).
    func sageElevationLow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}
