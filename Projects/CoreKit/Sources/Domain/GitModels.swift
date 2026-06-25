import Foundation

/// Частота авто-синхронизации Git.
public enum GitSyncFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case onChange
    case every5min
    case hourly
    case manual

    public var id: String { rawValue }

    /// Интервал периодического таймера авто-sync в секундах. nil — таймера нет:
    /// `.onChange` синхронизируется по дебаунсу правок, `.manual` — только по кнопке.
    public var autoIntervalSeconds: Double? {
        switch self {
        case .every5min: 300
        case .hourly: 3600
        case .onChange, .manual: nil
        }
    }

    /// Синхронизировать ли по факту локальных правок (дебаунс).
    public var syncsOnChange: Bool { self == .onChange }

    /// Включена ли вообще авто-синхронизация (любой триггер, кроме чисто ручного).
    public var isAutomatic: Bool { self != .manual }
}

/// Информация о подключённом репозитории.
public struct GitRepoInfo: Sendable, Equatable, Codable {
    public var remoteURL: String
    public var branch: String
    public var lastSync: Date?
    public var isClean: Bool

    public init(remoteURL: String, branch: String, lastSync: Date? = nil, isClean: Bool = true) {
        self.remoteURL = remoteURL
        self.branch = branch
        self.lastSync = lastSync
        self.isClean = isClean
    }
}

/// Один коммит для списка «Последние коммиты».
public struct GitCommit: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let shortHash: String
    public let message: String
    public let date: Date

    public init(id: String, shortHash: String, message: String, date: Date) {
        self.id = id
        self.shortHash = shortHash
        self.message = message
        self.date = date
    }
}

/// Результат операции синхронизации (для тостов). Семантические КОДЫ, а не готовый текст —
/// локализуются в UI-слое (`gitSyncToast`), чтобы статус не вылезал на чужом языке.
public enum GitSyncOutcome: Sendable, Equatable {
    case synced(pushed: Int)
    case conflict(file: String)
    case upToDate
    case noRepo
    case unrelatedHistories
    case failed(reason: String)
}
