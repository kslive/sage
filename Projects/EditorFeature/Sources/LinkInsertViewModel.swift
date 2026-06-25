import CoreKit
import Foundation
import Observation

/// Логика поповера вставки ссылки (Notion-стиль): режим URL / выбор .md-заметки + создание.
/// Чистая бизнес-логика — тестируется с MockVaultServicing.
@MainActor
@Observable
public final class LinkInsertViewModel {
    public enum Mode: Sendable, Hashable { case url, note }

    public struct NoteHit: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let relPath: String
        public let url: URL
    }

    public var mode: Mode = .url
    public var text: String
    public var url: String = ""
    public var query: String = ""

    private let vault: VaultServicing
    private let vaultRoot: URL?
    private let currentFile: URL?
    private var allNotes: [URL] = []

    public init(selectedText: String, vault: VaultServicing, vaultRoot: URL?, currentFile: URL?) {
        self.text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vault = vault
        self.vaultRoot = vaultRoot
        self.currentFile = currentFile
    }

    public func load() async {
        guard let root = vaultRoot else { allNotes = []; return }
        let cur = currentFile?.standardizedFileURL
        allNotes = (await vault.allMarkdownFiles(under: root)).filter { $0.standardizedFileURL != cur }
    }

    private func relPath(_ u: URL) -> String { vaultRoot.map { u.relativePath(from: $0) } ?? u.lastPathComponent }

    /// Заметки, отфильтрованные по имени ИЛИ относительному пути (подстрока, регистронезависимо).
    public var filteredNotes: [NoteHit] {
        let q = query.normalizedSearchKey
        return allNotes.compactMap { u in
            let title = u.deletingPathExtension().lastPathComponent
            let rel = relPath(u)
            if !q.isEmpty, !title.lowercased().contains(q), !rel.lowercased().contains(q) { return nil }
            return NoteHit(id: u.path, title: title, relPath: rel, url: u)
        }
    }

    /// «Создать заметку «query»» — nil, если query пуст или такая заметка уже есть.
    public var createSuggestion: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let exists = allNotes.contains { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(q) == .orderedSame }
        return exists ? nil : q
    }

    public var canAddURL: Bool { !url.trimmingCharacters(in: .whitespaces).isEmpty }

    private var label: String {
        let t = text.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? "ссылка" : q
    }

    public func buildURLLink() -> String { Self.buildLink(label: label, dest: url.trimmingCharacters(in: .whitespaces)) }
    public func noteLink(_ u: URL) -> String { Self.buildLink(label: label, dest: relPath(u)) }

    /// Создать заметку (папка = папка текущего файла, фолбэк — корень) и вернуть ссылку на неё.
    public func createAndLink() async -> String? {
        guard let name = createSuggestion else { return nil }
        guard let folder = currentFile?.deletingLastPathComponent() ?? vaultRoot else { return nil }
        guard let created = try? await vault.createNote(named: name, content: "# \(name)\n", in: folder) else { return nil }
        allNotes.append(created)
        return Self.buildLink(label: label, dest: relPath(created))
    }

    /// Чистое: `[label](dest)`, пробелы в dest → `<...>`. Зеркалит core.js `buildLink`.
    static func buildLink(label: String, dest: String) -> String {
        let stripped = label.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespaces)
        let lab = stripped.isEmpty ? "ссылка" : stripped
        let d = dest.rangeOfCharacter(from: .whitespaces) != nil ? "<\(dest)>" : dest
        return "[\(lab)](\(d))"
    }
}
