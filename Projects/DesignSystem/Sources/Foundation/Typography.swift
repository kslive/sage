import AppKit
import SwiftUI

/// Доступность кастомных шрифтов (Fontshare). При отсутствии — системный фолбэк.
public enum SageFontFamily {
    public static let display = "CabinetGrotesk-Bold"
    public static let displayHeavy = "CabinetGrotesk-Extrabold"
    public static let textRegular = "GeneralSans-Regular"
    public static let textMedium = "GeneralSans-Medium"
    public static let textSemibold = "GeneralSans-Semibold"
    public static let textBold = "GeneralSans-Bold"

    static func isAvailable(_ name: String) -> Bool {
        NSFont(name: name, size: 12) != nil
    }

    /// Системный SF при тех же px плотнее/крупнее, чем General Sans / Cabinet Grotesk из макета.
    /// Пока кастомные шрифты не забандлены — компенсируем масштабом, чтобы плотность совпадала
    /// с эталоном (иначе весь UI выглядит «крупнее макета»).
    private static let fallbackScale: CGFloat = 0.93

    static func font(_ name: String, size: CGFloat, systemWeight: Font.Weight, design: Font.Design = .default) -> Font {
        if isAvailable(name) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: (size * fallbackScale).rounded(), weight: systemWeight, design: design)
    }
}

/// Типографическая шкала из дизайн-системы (px → SwiftUI).
public enum SageTextStyle {
    case displayXL
    case h1
    case h2
    case h3
    case body
    case ui
    case uiMedium
    case caption
    case mono

    var font: Font {
        switch self {
        case .displayXL: SageFontFamily.font(SageFontFamily.displayHeavy, size: 34, systemWeight: .heavy)
        case .h1: SageFontFamily.font(SageFontFamily.display, size: 25, systemWeight: .bold)
        case .h2: SageFontFamily.font(SageFontFamily.display, size: 21, systemWeight: .bold)
        case .h3: SageFontFamily.font(SageFontFamily.textSemibold, size: 17, systemWeight: .semibold)
        case .body: SageFontFamily.font(SageFontFamily.textRegular, size: 15, systemWeight: .regular)
        case .ui: SageFontFamily.font(SageFontFamily.textRegular, size: 13.5, systemWeight: .regular)
        case .uiMedium: SageFontFamily.font(SageFontFamily.textMedium, size: 13.5, systemWeight: .medium)
        case .caption: SageFontFamily.font(SageFontFamily.textSemibold, size: 11, systemWeight: .semibold)
        case .mono: .system(size: 13, weight: .regular, design: .monospaced)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .displayXL: -0.85
        case .h1: -0.5
        case .h2: -0.32
        case .caption: 0.44
        default: 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .body, .ui: 4
        default: 0
        }
    }
}

public extension Font {
    /// Шрифт дизайн-системы (General Sans) нужного размера/веса — замена ad-hoc `.system(size:)`,
    /// чтобы нативный UI совпадал с макетом, а не использовал системный SF.
    static func sage(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = SageFontFamily.textMedium
        case .semibold: name = SageFontFamily.textSemibold
        case .bold, .heavy, .black: name = SageFontFamily.textBold
        default: name = SageFontFamily.textRegular
        }
        return SageFontFamily.font(name, size: size, systemWeight: weight)
    }
}

public extension View {
    /// Применяет шрифт + межбуквенный интервал из дизайн-системы.
    func sageType(_ style: SageTextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
    }
}

public extension Text {
    func sageType(_ style: SageTextStyle) -> Text {
        font(style.font).tracking(style.tracking)
    }
}

private final class BundleToken {}

/// Регистрация кастомных шрифтов из бандла DesignSystem (если они добавлены).
/// При отсутствии шрифтов типографика использует системный фолбэк.
public enum SageFonts {
    private static var registered = false

    public static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        let bundle = Bundle(for: BundleToken.self)
        var bundles = [bundle]
        if let nested = bundle.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
            bundles.append(contentsOf: nested.compactMap { Bundle(url: $0) })
        }
        for current in bundles {
            for ext in ["otf", "ttf"] {
                let urls = current.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
                let fontURLs = current.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
                for url in urls + fontURLs {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }
    }
}
