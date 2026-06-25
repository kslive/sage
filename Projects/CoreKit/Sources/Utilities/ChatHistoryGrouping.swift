import Foundation

public extension ChatContext {
    /// Mono-путь для строки истории (без счётчика): vault → «Всё хранилище», файл → relPath с .md,
    /// папка → «Name/» (относительно корня), выделение → имя файла.
    func historyPath(vaultRoot: URL?) -> String {
        switch self {
        case .vault:
            return "Всё хранилище"
        case let .file(name, path):
            let url = URL(fileURLWithPath: path)
            return vaultRoot.map { url.relativePath(from: $0) } ?? (name.hasSuffix(".md") ? name : name + ".md")
        case let .folder(name, _, path):
            let url = URL(fileURLWithPath: path)
            let rel = vaultRoot.map { url.relativePath(from: $0) } ?? name
            return rel + "/"
        case let .selection(fileName):
            return fileName
        }
    }
}

/// Группировка истории чатов по корзинам времени (Сегодня / Вчера / Ранее).
public enum ChatHistory {
    public enum Bucket: String, Sendable, Equatable, CaseIterable {
        case today
        case yesterday
        case earlier
    }

    public static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> Bucket {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }

    /// Сгруппировать сессии (порядок внутри корзины сохраняется как пришёл — обычно desc по updatedAt).
    /// Пустые корзины опускаются; порядок корзин — today → yesterday → earlier.
    public static func group(_ sessions: [ChatSession], now: Date, calendar: Calendar = .current)
        -> [(bucket: Bucket, sessions: [ChatSession])] {
        var map: [Bucket: [ChatSession]] = [:]
        for session in sessions {
            map[bucket(for: session.updatedAt, now: now, calendar: calendar), default: []].append(session)
        }
        return Bucket.allCases.compactMap { b in map[b].map { (b, $0) } }
    }
}
