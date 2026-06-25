import Foundation
import Observation

/// Единый источник правды о фоновых задачах ИИ (in-memory, на сессию). Пишут VM (старт/финиш/ошибка),
/// читают сайдбар/чат-навигация (спиннер/свечение/бейдж), App чистит при просмотре/удалении.
@MainActor
@Observable
public final class AITaskRegistry {
    public private(set) var entries: [String: AITaskEntry] = [:]

    public init() {}

    public func started(_ key: AITaskKey, label: String, route: AITaskRoute) {
        entries[key.raw] = AITaskEntry(phase: .running, label: label, route: route)
    }

    public func finished(_ key: AITaskKey) { transition(key, to: .readyUnread) }
    public func failed(_ key: AITaskKey) { transition(key, to: .error) }

    private func transition(_ key: AITaskKey, to phase: AITaskPhase) {
        guard var entry = entries[key.raw] else { return }
        entry.phase = phase
        entry.updatedAt = Date()
        entries[key.raw] = entry
    }

    /// Просмотрено → запись снимается (свечение/бейдж гаснут). НО идущую генерацию (.running)
    /// НЕ трогаем — иначе клик по лоадеру/открытие чата гасил спиннер до завершения.
    public func markRead(_ key: AITaskKey) {
        if entries[key.raw]?.phase == .running { return }
        entries[key.raw] = nil
    }
    public func markRead(raw: String) {
        if entries[raw]?.phase == .running { return }
        entries[raw] = nil
    }

    /// Принудительно снять задачу (юзер ОТМЕНИЛ генерацию / удалил чат) — в т.ч. идущую (.running),
    /// в отличие от markRead (который running не трогает, чтобы навигация не гасила спиннер).
    public func cancel(_ key: AITaskKey) { entries[key.raw] = nil }

    // MARK: - Чтение (для UI; чистые лукапы)

    public func phase(_ key: AITaskKey) -> AITaskPhase? { entries[key.raw]?.phase }
    public func isRunning(_ key: AITaskKey) -> Bool { phase(key) == .running }
    public func isReadyUnread(_ key: AITaskKey) -> Bool { phase(key) == .readyUnread }

    /// Бейдж папки: чат по этой папке готов и не прочитан.
    public func folderHasUnread(path: String) -> Bool {
        entries["folder:\(path)"]?.phase == .readyUnread
    }

    /// Снять записи, не прошедшие фильтр (App вызывает на удаление/смену хранилища).
    public func prune(keepRaw: (String) -> Bool) {
        for key in Array(entries.keys) where !keepRaw(key) { entries[key] = nil }
    }
}
