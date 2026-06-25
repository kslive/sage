import Foundation

/// Узел дерева файлов хранилища (папка или `.md` заметка).
public struct FileNode: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let depth: Int
    public var children: [FileNode]
    /// Дата изменения файла/папки — для сортировки сайдбара «по дате». Optional (может быть недоступна).
    public var modifiedAt: Date?

    public init(
        id: String? = nil, name: String, url: URL,
        isDirectory: Bool, depth: Int, children: [FileNode] = [], modifiedAt: Date? = nil
    ) {
        self.id = id ?? url.path
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.depth = depth
        self.children = children
        self.modifiedAt = modifiedAt
    }

    /// Плоское представление (с учётом раскрытых папок) для списков.
    public func flattened(expanded: Set<String>) -> [FileNode] {
        var result: [FileNode] = [self]
        if isDirectory, expanded.contains(id) {
            for child in children {
                result.append(contentsOf: child.flattened(expanded: expanded))
            }
        }
        return result
    }
}

/// Открытая заметка.
public struct NoteDocument: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public var text: String
    public var modifiedAt: Date

    public init(url: URL, text: String, modifiedAt: Date) {
        self.url = url
        self.text = text
        self.modifiedAt = modifiedAt
    }

    public var fileName: String { url.lastPathComponent }
    public var wordCount: Int { text.wordCount }
}

/// Элемент структуры документа (outline) для правого рейла.
public struct OutlineItem: Identifiable, Sendable, Equatable {
    public let id: Int
    public let level: Int
    public let text: String
    public let line: Int

    public init(id: Int, level: Int, text: String, line: Int = 0) {
        self.id = id
        self.level = level
        self.text = text
        self.line = line
    }
}
