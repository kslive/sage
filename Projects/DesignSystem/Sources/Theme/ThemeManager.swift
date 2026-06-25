import CoreKit
import Observation
import SwiftUI

/// Источник истины темы и акцента (рантайм-смена). Персистится в `UserDefaults`.
@Observable
public final class ThemeManager {
    public var mode: AppTheme {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: modeKey) }
    }

    public var accent: AccentPreset {
        didSet { UserDefaults.standard.set(accent.id, forKey: accentKey) }
    }

    private let modeKey = "sage.theme.mode"
    private let accentKey = "sage.theme.accent"

    public init(mode: AppTheme? = nil, accent: AccentPreset? = nil) {
        let savedMode = UserDefaults.standard.string(forKey: modeKey).flatMap(AppTheme.init(rawValue:))
        let savedAccent = UserDefaults.standard.string(forKey: accentKey).map(AccentPreset.preset(id:))
        self.mode = mode ?? savedMode ?? .auto
        self.accent = accent ?? savedAccent ?? .green
    }

    public func isDarkResolved(system isSystemDark: Bool) -> Bool {
        switch mode {
        case .dark: true
        case .light: false
        case .auto: isSystemDark
        }
    }

    public func palette(systemDark: Bool) -> ThemePalette {
        isDarkResolved(system: systemDark) ? .dark(accent: accent) : .light(accent: accent)
    }

    /// Для `.preferredColorScheme` (nil = следовать системе).
    public var preferredColorScheme: ColorScheme? {
        switch mode {
        case .dark: .dark
        case .light: .light
        case .auto: nil
        }
    }

    public func cycle() {
        let order: [AppTheme] = [.dark, .light, .auto]
        let index = order.firstIndex(of: mode) ?? 0
        mode = order[(index + 1) % order.count]
    }
}
