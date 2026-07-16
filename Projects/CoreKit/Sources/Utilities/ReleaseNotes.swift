import Foundation

/// Вырезает из тела GitHub-релиза локализованную часть для окна «Что нового».
/// Нотсы Sage трёхъязычные (`## 🇬🇧 English`, `## 🇷🇺 Русский`, `## 🇨🇳 中文`) с общим
/// футером после последнего `---` (SHA-256) и install-инструкциями внутри каждой секции —
/// пользователю после обновления нужен только блок «Что нового».
public enum ReleaseNotes {
    private static func markers(for language: AppLanguage) -> [String] {
        switch language {
        case .en: ["🇬🇧", "English"]
        case .ru: ["🇷🇺", "Русск"]
        case .zh: ["🇨🇳", "中文"]
        }
    }

    private static let allMarkers = ["🇬🇧", "English", "🇷🇺", "Русск", "🇨🇳", "中文"]

    /// Строки, с которых начинается служебный хвост секции (инструкции по обновлению/установке) —
    /// в анонсе не нужны: приложение уже обновилось.
    private static let tailMarkers = [
        "**Обновление с", "**Updating from", "**从",
        "**Чистая установка", "**Fresh install", "**全新安装",
        "**Требования", "**Requires", "**系统要求",
    ]

    /// Локализованная секция нотсов (футер отрезан). Фолбэк — всё тело без футера,
    /// когда языковых секций нет (не-трёхъязычные нотсы).
    public static func localizedSection(_ body: String, language: AppLanguage) -> String {
        let stripped = stripFooter(body)
        let lines = stripped.components(separatedBy: "\n")
        let wanted = markers(for: language)

        var collected: [String] = []
        var inSection = false
        for line in lines {
            let isHeading = line.hasPrefix("## ")
            if isHeading, wanted.contains(where: { line.contains($0) }) {
                inSection = true
                continue
            }
            if isHeading, allMarkers.contains(where: { line.contains($0) }) {
                if inSection { break }
                continue
            }
            if inSection { collected.append(line) }
        }
        let section = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? stripped : section
    }

    /// Готовый текст для окна «Что нового»: локализованная секция без install-хвоста.
    public static func announcement(_ body: String, language: AppLanguage) -> String {
        let section = localizedSection(body, language: language)
        let lines = section.components(separatedBy: "\n")
        if let cut = lines.firstIndex(where: { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return tailMarkers.contains(where: { t.hasPrefix($0) })
        }) {
            let head = lines[..<cut].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Хвостовой разделитель «---» перед отрезанной частью тоже не нужен.
            let cleaned = head.hasSuffix("---") ? String(head.dropLast(3)) : head
            let result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty { return result }
        }
        return section
    }

    /// Отрезает всё от ПОСЛЕДНЕГО `---` (SHA-256-футер).
    static func stripFooter(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        if let cut = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            return lines[..<cut].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
