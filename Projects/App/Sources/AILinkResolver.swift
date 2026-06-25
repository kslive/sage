import CoreKit
import Foundation

/// Чистый резолвер заметок/ссылок ИИ по дереву хранилища (без vault/async/ИИ-стейта) — выделен из
/// `RealAICoordinator` ради тестируемости. Резолв цели по полному пути/leaf/fuzzy, поиск узла по
/// сегментам, нормализация markdown-ссылок (пробелы → `<...>`), первая строка заметки.
struct AILinkResolver {
    let tree: FileNode?
    let current: URL?

    /// Путь для markdown-ссылки: пробелы → угловые скобки `<...>` (CommonMark), иначе ломается.
    static func mdPath(_ rel: String) -> String {
        rel.contains(" ") ? "<\(rel)>" : rel
    }

    /// Первая непустая строка заметки (для краткой выдержки в списке папки).
    static func firstLine(_ text: String) -> String {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#>*-").union(.whitespaces))
            if !line.isEmpty { return String(line.prefix(90)) }
        }
        return ""
    }

    /// Резолвит цель ссылки: алиасы «эта заметка» → current; затем точный полный путь; leaf; fuzzy.
    func resolveNote(_ target: String) -> URL? {
        let low = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = ["this note", "current note", "the note", "this file", "open note",
                       "эта заметка", "эту заметку", "этой заметке", "данная заметка", "данную заметку",
                       "данной заметке", "текущая заметка", "текущую заметку", "этот файл"]
        if let current, aliases.contains(where: { low.contains($0) }) { return current }
        var cleaned = target.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        cleaned = cleaned.removingPercentEncoding ?? cleaned
        let wanted = cleaned.withoutMDExtension
        if wanted.contains("/"), let full = Self.findNode(in: tree, isDir: false, name: wanted)?.url { return full }
        let leaf = wanted.contains("/") ? String(wanted.split(separator: "/").last ?? "") : wanted
        if let exact = Self.findNode(in: tree, isDir: false, name: leaf)?.url { return exact }
        if let fuzzy = Self.findNoteContaining(leaf.lowercased(), in: tree) { return fuzzy }
        return nil
    }

    static func findNode(in node: FileNode?, isDir: Bool, name: String) -> FileNode? {
        guard let node else { return nil }
        let parts = name.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if parts.count > 1 {
            var current: FileNode? = node
            for (i, seg) in parts.enumerated() {
                let wantDir = i < parts.count - 1 ? true : isDir
                current = directChild(of: current, isDir: wantDir, name: seg)
                if current == nil { return nil }
            }
            return current
        }
        for child in node.children {
            if child.isDirectory == isDir {
                let base = child.isDirectory ? child.name : child.name.withoutMDExtension
                if base.localizedCaseInsensitiveCompare(name) == .orderedSame { return child }
            }
            if child.isDirectory, let found = findNode(in: child, isDir: isDir, name: name) { return found }
        }
        return nil
    }

    /// Прямой потомок узла по имени (без рекурсии) — для разбора вложенных путей.
    static func directChild(of node: FileNode?, isDir: Bool, name: String) -> FileNode? {
        guard let node else { return nil }
        let target = name.withoutMDExtension
        return node.children.first { child in
            guard child.isDirectory == isDir else { return false }
            let base = child.isDirectory ? child.name : child.name.withoutMDExtension
            return base.localizedCaseInsensitiveCompare(target) == .orderedSame
        }
    }

    static func findNoteContaining(_ q: String, in node: FileNode?) -> URL? {
        guard let node, !q.isEmpty else { return nil }
        for child in node.children {
            if !child.isDirectory {
                let base = child.name.withoutMDExtension.lowercased()
                if base.contains(q) { return child.url }
            }
            if child.isDirectory, let found = findNoteContaining(q, in: child) { return found }
        }
        return nil
    }

    /// Заметки для массового удаления: по имени папки (все .md внутри) ИЛИ по имени/вхождению.
    /// Понимает «Notes», «Notes/», «Notes/*.md», «*.md», имена заметок.
    static func matchingNotes(_ q: String, tree: FileNode?) -> [URL] {
        var s = q.lowercased().trimmingCharacters(in: .whitespaces)
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        s = s.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: ".md", with: "")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ". /\"'"))
        guard !s.isEmpty else { return [] }
        if let folder = findNode(in: tree, isDir: true, name: s) {
            var out: [URL] = []
            func collect(_ n: FileNode) { for c in n.children { if c.isDirectory { collect(c) } else { out.append(c.url) } } }
            collect(folder)
            return out
        }
        var out: [URL] = []
        func walk(_ node: FileNode?) {
            guard let node else { return }
            for child in node.children {
                if child.isDirectory { walk(child) }
                else {
                    let base = child.name.withoutMDExtension.lowercased()
                    if base == s || base.contains(s) { out.append(child.url) }
                }
            }
        }
        walk(tree)
        return out
    }
}
