import Foundation

public enum EditorMode: String, Sendable, Equatable {
    case preview
    case markdown
}

public enum EditorVariant: String, Sendable, Equatable {
    case a
    case b
}

/// Тип инлайн-ИИ действия (⌘J).
public enum AIAction: String, Sendable {
    case ask
    case continueText
    case summary
    case improve
    case transform
}
