import Foundation

/// Тип всплывающего уведомления.
public enum ToastKind: Sendable, Equatable {
    case success
    case error
    case info
}

/// Всплывающее уведомление (внизу справа).
public struct Toast: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let icon: String
    public let text: String
    /// Подзаголовок (mono-путь «в Daily/2026-06-21.md») — для двухстрочной actionable-карты.
    public let subtitle: String?
    public let kind: ToastKind
    /// Опциональное действие «Открыть» (для приглашения «Sage ответил … · Открыть»).
    public let action: ToastAction?

    public init(id: UUID = UUID(), icon: String, text: String, subtitle: String? = nil,
                kind: ToastKind = .success, action: ToastAction? = nil) {
        self.id = id
        self.icon = icon
        self.text = text
        self.subtitle = subtitle
        self.kind = kind
        self.action = action
    }
}

/// Результат поиска по хранилищу.
public struct SearchResult: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let path: String
    public let snippet: String
    public let icon: String
    public let fileURL: URL?

    public init(id: String, title: String, path: String, snippet: String, icon: String, fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.path = path
        self.snippet = snippet
        self.icon = icon
        self.fileURL = fileURL
    }
}

/// Основные разделы навигации приложения.
public enum AppView: String, Sendable, Equatable {
    case editor
    case chat
    case settings
}

/// Какой узел подсветить в сайдбаре. В режиме чата — папка/файл АКТИВНОГО контекста чата
/// (а не последний открытый в редакторе файл); иначе — открытый в редакторе файл.
/// `.vault`/`.selection` в чате → ничего (нет конкретного узла).
public func sidebarHighlightID(view: AppView, chatContext: ChatContext, editorFile: String?) -> String? {
    if view == .chat {
        switch chatContext {
        case let .file(_, path): return path
        case let .folder(_, _, path): return path
        case .vault, .selection: return nil
        }
    }
    return editorFile
}

/// Вкладки настроек.
public enum SettingsTab: String, CaseIterable, Sendable, Identifiable {
    case general
    case ai
    case appearance
    case git
    case updates
    case about

    public var id: String { rawValue }
    public var iconSymbol: String {
        switch self {
        case .general: "gearshape"
        case .ai: "sparkle"
        case .appearance: "circle.lefthalf.filled"
        case .git: "arrow.triangle.branch"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}
