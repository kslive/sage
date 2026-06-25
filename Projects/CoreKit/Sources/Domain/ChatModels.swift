import Foundation

public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

/// Сообщение в чате.
public struct ChatMessage: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let role: ChatRole
    public var text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// Контекст, к которому привязан чат.
public enum ChatContext: Sendable, Equatable, Codable, Hashable {
    case vault
    case file(name: String, path: String)
    case folder(name: String, fileCount: Int, path: String)
    case selection(fileName: String)

    public var iconSymbol: String {
        switch self {
        case .vault: "sparkles"
        case .file: "doc.text"
        case .folder: "folder"
        case .selection: "text.quote"
        }
    }
}

/// Фаза голосового ввода.
public enum VoicePhase: String, Sendable, Equatable {
    case off
    case permission
    case listening
    case transcribing
}

/// Показывать ли orb-оверлей голоса (и СКРЫВАТЬ хедер чата + поле ввода): во всех фазах кроме `.off`.
/// Чистая логика (тест: инпут/хедер скрыты на всём голосовом потоке, не мелькают при ✓/Enter-автоотправке).
public func voiceShowsOrbOverlay(_ phase: VoicePhase) -> Bool { phase != .off }

/// Сессия чата (история привязана к файлам/папкам).
public struct ChatSession: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public var title: String
    public var context: ChatContext
    public var messages: [ChatMessage]
    public var updatedAt: Date
    /// Воркспейс (vault), к которому относится сессия — чтобы история не «протекала» между папками.
    /// Optional — для обратной совместимости со старыми сессиями без этого поля.
    public var vaultPath: String?

    public init(
        id: UUID = UUID(), title: String, context: ChatContext,
        messages: [ChatMessage] = [], updatedAt: Date = Date(), vaultPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.messages = messages
        self.updatedAt = updatedAt
        self.vaultPath = vaultPath
    }
}
