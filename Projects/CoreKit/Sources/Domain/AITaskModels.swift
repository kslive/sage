import Foundation

/// Фаза фоновой задачи ИИ.
public enum AITaskPhase: Sendable, Equatable {
    case running
    case readyUnread
    case error
}

/// Как «открыть» задачу из тоста/индикатора (резолвит App, который знает AppRouter).
public enum AITaskRoute: Sendable, Equatable {
    case openChat(ChatContext)
    case openInline(path: String)
    case openUpdates
    case restartUpdate
}

/// Канонический ключ задачи. Строка `.raw` совпадает со схемой chatKey приложения
/// (vault / file:<path> / folder:<path> / selection:<name>) + пространство inline:<path>.
public enum AITaskKey: Sendable, Hashable {
    case chat(ChatContext)
    case inline(path: String)

    public var raw: String {
        switch self {
        case let .chat(ctx):
            switch ctx {
            case .vault: return "vault"
            case let .file(_, path): return "file:\(path)"
            case let .folder(_, _, path): return "folder:\(path)"
            case let .selection(name): return "selection:\(name)"
            }
        case let .inline(path): return "inline:\(path)"
        }
    }
}

/// Запись реестра задач.
public struct AITaskEntry: Sendable, Equatable {
    public var phase: AITaskPhase
    public var label: String
    public var route: AITaskRoute
    public var updatedAt: Date

    public init(phase: AITaskPhase, label: String, route: AITaskRoute, updatedAt: Date = Date()) {
        self.phase = phase
        self.label = label
        self.route = route
        self.updatedAt = updatedAt
    }
}

/// Действие тоста «Открыть» (без замыкания → Toast остаётся Equatable/Sendable).
public struct ToastAction: Sendable, Equatable {
    public let label: String
    public let route: AITaskRoute
    public init(label: String, route: AITaskRoute) {
        self.label = label
        self.route = route
    }
}
