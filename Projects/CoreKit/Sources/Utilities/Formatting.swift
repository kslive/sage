import Foundation

/// Утилиты форматирования размеров/скорости/времени с учётом локали.
public enum Formatting {
    public static func fileSize(_ bytes: Int64, locale: Locale = .current) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Скорость загрузки «5.0 <unit>». `unit` — локализованная единица («МБ/с»/«MB/s»/«MB/秒»).
    public static func speed(bytesPerSec: Double, unit: String) -> String {
        let mbps = bytesPerSec / (1024 * 1024)
        let value = mbps >= 10 ? String(format: "%.0f", mbps) : String(format: "%.1f", mbps)
        return "\(value) \(unit)"
    }

    /// Прогресс «2.9 / 4.7 ГБ».
    public static func progress(done: Int64, total: Int64) -> String {
        "\(fileSize(done)) / \(fileSize(total))"
    }

    public static func relativeTime(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Относительное время, но при разнице < 60с → локализованное «только что» (`justNow`).
    /// Чинит баг `RelativeDateTimeFormatter`: при интервале ≈0 он даёт будущее «через 0 сек».
    public static func relativeOrJustNow(_ date: Date, now: Date = Date(), justNow: String,
                                         locale: Locale = .current) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return justNow }
        return relativeTime(date, now: now, locale: locale)
    }

    /// Пора ли делать фоновую проверку обновлений: прошёл ли `interval` с `last` (nil → да). Чистая фн (тест).
    public static func shouldCheck(last: Date?, now: Date = Date(), interval: TimeInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Таймер записи «m:ss» (6→«0:06», 75→«1:15»). Отрицательное → «0:00». Чистая фн (тест голосового ввода).
    public static func elapsedClock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// Склейка набранного текста с распознанным (голос): пустой префикс → только распознанное,
    /// иначе «префикс + пробел + распознанное». Единая для partial/finished → нет двойного текста. Тест.
    public static func mergeVoiceText(prefix: String, transcript: String) -> String {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return prefix }
        return prefix.isEmpty ? t : prefix + " " + t
    }

    /// Строка с датами для системного промпта ИИ: сегодня + вчера + день недели (ISO YYYY-MM-DD).
    /// Чтобы модель понимала «вчера/сегодня» без хрупкой арифметики (заметки названы по дате).
    public static func dateContext(now: Date = Date(), calendar: Calendar = .current) -> String {
        let iso = DateFormatter()
        iso.calendar = calendar; iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd"
        let wd = DateFormatter(); wd.calendar = calendar; wd.locale = Locale(identifier: "en_US"); wd.dateFormat = "EEEE"
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return "Today is \(iso.string(from: now)) (\(wd.string(from: now))). Yesterday was \(iso.string(from: yesterday)). Note files are often named by date YYYY-MM-DD; use search_notes with the date to find notes for a given day."
    }

    /// Сообщение git-коммита: «Sage · <action> · 2026-06-24 17:30». `action` — локализованный глагол
    /// («автосинхронизация»/«auto-sync»/«自动同步»). Дата числовая (en_US_POSIX, локаль-независимо) —
    /// стабильна в git-истории. Чистая фн (дата инъектируется → тест).
    public static func gitCommitMessage(action: String, date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "Sage · \(action) · \(f.string(from: date))"
    }

}

public extension String {
    /// Имя без хвостового расширения `.md` (для отображения и сопоставления заметок).
    var withoutMDExtension: String {
        hasSuffix(".md") ? String(dropLast(3)) : self
    }

    /// Нормализованная цель markdown-ссылки: percent-decode + снять обрамляющие `<>`/пробелы.
    /// Единая для клика по ссылке в чате и редакторе (раньше дублировалось inline). Порядок важен:
    /// сначала decode, потом обрезка `<>` (CommonMark-обёртка путей с пробелами, Ит.51). [[editor-source]]
    var normalizedLinkTarget: String {
        (removingPercentEncoding ?? self).trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    /// Ключ запроса для регистронезависимого поиска/фильтра: trim пробелов + lowercase.
    var normalizedSearchKey: String {
        trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Количество слов (разбиение по пробелам и переводам строк).
    var wordCount: Int {
        split { $0 == " " || $0.isNewline }.count
    }
}

public extension URL {
    /// Путь относительно корня хранилища (для цитат ИИ); вне корня — последний компонент.
    func relativePath(from root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let selfComponents = standardizedFileURL.pathComponents
        if selfComponents.count >= rootComponents.count,
           Array(selfComponents.prefix(rootComponents.count)) == rootComponents {
            return selfComponents.dropFirst(rootComponents.count).joined(separator: "/")
        }
        return lastPathComponent
    }

    /// Сегменты хлебных крошек заметки относительно корня хранилища, у листа снят `.md`.
    /// `/V/Reference/python-shpargalka.md` от `/V` → `["Reference", "python-shpargalka"]`.
    /// Вне корня / без корня → `[лист без .md]`.
    func crumbSegments(from root: URL?) -> [String] {
        guard let root else { return [deletingPathExtension().lastPathComponent] }
        let rel = relativePath(from: root)
        var parts = rel.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return [deletingPathExtension().lastPathComponent] }
        parts[parts.count - 1] = parts[parts.count - 1].withoutMDExtension
        return parts
    }
}
