import Foundation

/// Пространство имён модуля CoreKit — общие доменные типы и протоколы,
/// не зависящие от UI (только Foundation). Используется всеми модулями.
public enum CoreKit {
    public static let appName = "Sage"
    /// Версия приложения — ЕДИНАЯ точка правды из бандла (Info.plist `CFBundleShortVersionString`
    /// = `MARKETING_VERSION`). Бамп одной строки в Module.swift. Фолбэк "1.0.0" — для тест-раннера
    /// (Bundle.main = xctest).
    public static let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
}
