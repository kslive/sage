import AppKit
import SwiftUI

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = .dark(accent: .green)
}

public extension EnvironmentValues {
    /// Текущая цветовая палитра. Компоненты читают `@Environment(\.palette)`.
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Контейнер, прокидывающий палитру вниз по дереву.
/// Палитра зависит ТОЛЬКО от `theme.mode`/`theme.accent` (без петли через colorScheme),
/// поэтому переключение темы срабатывает с первого клика.
public struct SageThemeContainer<Content: View>: View {
    private let theme: ThemeManager
    private let content: Content
    @State private var appearanceTick = 0

    public init(_ theme: ThemeManager, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.content = content()
    }

    public var body: some View {
        _ = appearanceTick
        let dark = resolvedDark()
        return content
            .environment(\.palette, theme.palette(systemDark: dark))
            .preferredColorScheme(theme.preferredColorScheme)
            .tint(theme.palette(systemDark: dark).ac)
            .onReceive(DistributedNotificationCenter.default().publisher(
                for: Notification.Name("AppleInterfaceThemeChangedNotification"))) { _ in
                appearanceTick &+= 1
            }
    }

    private func resolvedDark() -> Bool {
        switch theme.mode {
        case .dark: return true
        case .light: return false
        case .auto:
            let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
        }
    }
}

public extension View {
    /// Применяет тему Sage (палитра + системная схема) ко всему поддереву.
    func sageTheme(_ theme: ThemeManager) -> some View {
        SageThemeContainer(theme) { self }
    }
}
