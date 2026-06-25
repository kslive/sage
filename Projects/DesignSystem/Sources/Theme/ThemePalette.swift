import CoreKit
import SwiftUI

/// Полный набор цветовых токенов одной темы (значения из Sage-Design-System).
public struct ThemePalette: Sendable, Equatable {
    public let bg: Color
    public let bg1: Color
    public let bg2: Color
    public let bg3: Color
    public let bgh: Color
    public let inp: Color
    public let bd: Color
    public let bd2: Color
    public let tx: Color
    public let tx2: Color
    public let tx3: Color
    public let ac: Color
    public let acs: Color
    public let error: Color
    public let obTop: Color
    public let menubar: Color
    public let shadow: Color
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat
    public let isDark: Bool

    /// Кнопочный текст поверх акцента (тёмный на зелёном).
    public let onAccent: Color

    /// Идентификатор акцента (для стабильного `key`).
    public let accentID: String

    /// Стабильный ключ идентичности темы (НЕ из `Color`-описаний — те на macOS не различимы).
    /// Меняется при смене схемы (dark/light) ИЛИ акцента → пригоден для `.id(palette.key)`,
    /// чтобы пересоздавать `NSTextField` (он кэширует `textColor`) при смене темы.
    public var key: String { "\(isDark ? "d" : "l")_\(accentID)" }

    public let trafficClose = Color(hex: "#FF5F57")
    public let trafficMin = Color(hex: "#FEBC2E")
    public let trafficZoom = Color(hex: "#28C840")

    public static func dark(accent: AccentPreset) -> ThemePalette {
        ThemePalette(
            bg: Color(hex: "#08090A"), bg1: Color(hex: "#0B0C0D"), bg2: Color(hex: "#101113"),
            bg3: Color(hex: "#17181B"), bgh: Color(white: 1, opacity: 0.045), inp: Color(hex: "#1B1D20"),
            bd: Color(white: 1, opacity: 0.08), bd2: Color(white: 1, opacity: 0.13),
            tx: Color(hex: "#F7F8F8"), tx2: Color(hex: "#9499A1"), tx3: Color(hex: "#6A6F78"),
            ac: Color(hex: accent.darkHex), acs: Color(hex: accent.darkHex).opacity(0.13),
            error: Color(hex: "#FF8A8A"), obTop: Color(hex: "#0F1417"),
            menubar: Color(red: 12 / 255, green: 13 / 255, blue: 14 / 255, opacity: 0.7),
            shadow: Color.black.opacity(0.55), shadowRadius: 24, shadowY: 14, isDark: true,
            onAccent: Color(hex: "#04140C"), accentID: accent.id
        )
    }

    public static func light(accent: AccentPreset) -> ThemePalette {
        ThemePalette(
            bg: Color(hex: "#FFFFFF"), bg1: Color(hex: "#FBFBFA"), bg2: Color(hex: "#FFFFFF"),
            bg3: Color(hex: "#EEEEEC"), bgh: Color(white: 0, opacity: 0.04), inp: Color(hex: "#F4F4F3"),
            bd: Color(white: 0, opacity: 0.09), bd2: Color(white: 0, opacity: 0.15),
            tx: Color(hex: "#1C1D1F"), tx2: Color(hex: "#62666C"), tx3: Color(hex: "#9AA0A6"),
            ac: Color(hex: accent.lightHex), acs: Color(hex: accent.lightHex).opacity(0.10),
            error: Color(hex: "#EB5757"), obTop: Color(hex: "#EEF1EE"),
            menubar: Color(red: 12 / 255, green: 13 / 255, blue: 14 / 255, opacity: 0.72),
            shadow: Color.black.opacity(0.14), shadowRadius: 24, shadowY: 14, isDark: false,
            onAccent: Color.white, accentID: accent.id
        )
    }

    public init(
        bg: Color, bg1: Color, bg2: Color, bg3: Color, bgh: Color, inp: Color,
        bd: Color, bd2: Color, tx: Color, tx2: Color, tx3: Color, ac: Color, acs: Color,
        error: Color, obTop: Color, menubar: Color, shadow: Color,
        shadowRadius: CGFloat, shadowY: CGFloat, isDark: Bool, onAccent: Color,
        accentID: String = "green"
    ) {
        self.bg = bg; self.bg1 = bg1; self.bg2 = bg2; self.bg3 = bg3; self.bgh = bgh; self.inp = inp
        self.bd = bd; self.bd2 = bd2; self.tx = tx; self.tx2 = tx2; self.tx3 = tx3
        self.ac = ac; self.acs = acs; self.error = error; self.obTop = obTop; self.menubar = menubar
        self.shadow = shadow; self.shadowRadius = shadowRadius; self.shadowY = shadowY
        self.isDark = isDark; self.onAccent = onAccent; self.accentID = accentID
    }
}
