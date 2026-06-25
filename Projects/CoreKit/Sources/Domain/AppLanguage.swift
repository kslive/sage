import Foundation

/// Поддерживаемые языки интерфейса (переключаются в рантайме).
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case ru
    case en
    case zh

    public var id: String { rawValue }

    /// Выбрать язык по системным предпочтениям (`Locale.preferredLanguages`): первый код,
    /// который мы поддерживаем (ru / zh-* → zh / en), иначе НЕЙТРАЛЬНЫЙ английский (а не русский).
    /// Чистая функция — тестируется без системной локали. Передавать `Locale.preferredLanguages`.
    public static func fromSystem(_ codes: [String]) -> AppLanguage {
        for code in codes {
            let lower = code.lowercased()
            if lower.hasPrefix("ru") { return .ru }
            if lower.hasPrefix("zh") { return .zh }
            if lower.hasPrefix("en") { return .en }
        }
        return .en
    }

    /// Идентификатор локали для `Bundle`.
    public var localeIdentifier: String {
        switch self {
        case .ru: "ru"
        case .en: "en"
        case .zh: "zh-Hans"
        }
    }

    /// Короткая метка для сегмент-переключателя.
    public var menuLabel: String {
        switch self {
        case .ru: "Рус"
        case .en: "EN"
        case .zh: "中文"
        }
    }

    /// Название на самом языке.
    public var nativeName: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        case .zh: "中文"
        }
    }

    /// Английское название языка (для системных промптов ИИ).
    public var englishName: String {
        switch self {
        case .ru: "Russian"
        case .en: "English"
        case .zh: "Chinese"
        }
    }

    public var flag: String {
        switch self {
        case .ru: "🇷🇺"
        case .en: "🇬🇧"
        case .zh: "🇨🇳"
        }
    }

    /// Локализованное «N файлов» для подписи контекста-папки в истории чата.
    /// RU — 3-форма согласования; EN — file/files; ZH — без множественного. Чистая фн (тест).
    public func filesCount(_ n: Int) -> String {
        switch self {
        case .ru:
            let a = abs(n) % 100, b = abs(n) % 10
            let word: String
            if a >= 11, a <= 14 { word = "файлов" }
            else if b == 1 { word = "файл" }
            else if b >= 2, b <= 4 { word = "файла" }
            else { word = "файлов" }
            return "\(n) \(word)"
        case .en: return n == 1 ? "1 file" : "\(n) files"
        case .zh: return "\(n) 个文件"
        }
    }
}
