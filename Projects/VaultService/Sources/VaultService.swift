import CoreKit
import Foundation

/// Доступ к хранилищу заметок (файловая система).
public actor VaultService: VaultServicing {
    private let fm = FileManager.default

    public init() {}

    public func buildTree(at root: URL) async throws -> FileNode {
        try node(at: root, depth: -1, isRoot: true)
    }

    private func node(at url: URL, depth: Int, isRoot: Bool = false) throws -> FileNode {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let isDir = values.isDirectory ?? false
        let modified = values.contentModificationDate
        var children: [FileNode] = []
        if isDir {
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let dirs = contents.filter {
                guard (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
                let name = $0.lastPathComponent
                return name != "assets" && !name.hasPrefix(".")
            }
            let files = contents.filter { $0.pathExtension.lowercased() == "md" }
            let sortedDirs = dirs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            let sortedFiles = files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for child in sortedDirs + sortedFiles {
                if let childNode = try? node(at: child, depth: depth + 1) {
                    children.append(childNode)
                }
            }
        }
        return FileNode(
            name: url.lastPathComponent,
            url: url,
            isDirectory: isDir,
            depth: max(0, depth),
            children: children,
            modifiedAt: modified
        )
    }

    public func readNote(at url: URL) async throws -> NoteDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let modified = (attrs?[.modificationDate] as? Date) ?? Date()
        return NoteDocument(url: url, text: text, modifiedAt: modified)
    }

    public func writeNote(_ document: NoteDocument) async throws {
        try document.text.write(to: document.url, atomically: true, encoding: .utf8)
    }

    public func createNote(named name: String, in folder: URL) async throws -> URL {
        try await createNote(named: name, content: "# \(name)\n\n", in: folder)
    }

    public func createNote(named name: String, content: String, in folder: URL) async throws -> URL {
        let safeBase = name.withoutMDExtension.replacingOccurrences(of: "/", with: "-")
        let target = uniquePath(base: safeBase, ext: "md", in: folder)
        let body = content.isEmpty ? "# \(safeBase)\n\n" : content
        try body.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    /// Уникальный путь в папке: при коллизии добавляет « 1», « 2», … (пустой ext → каталог).
    private func uniquePath(base: String, ext: String, in folder: URL) -> URL {
        let isDir = ext.isEmpty
        func make(_ stem: String) -> URL {
            folder.appendingPathComponent(isDir ? stem : "\(stem).\(ext)", isDirectory: isDir)
        }
        var target = make(base)
        var counter = 1
        while fm.fileExists(atPath: target.path) {
            target = make("\(base) \(counter)")
            counter += 1
        }
        return target
    }

    public func saveAsset(_ data: Data, ext: String, nearNote noteURL: URL) async throws -> String {
        let dir = noteURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        let safeExt = cleanExt.isEmpty ? "png" : cleanExt
        let stamp = Int(Date().timeIntervalSince1970)
        var name = "image-\(stamp).\(safeExt)"
        var counter = 1
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "image-\(stamp)-\(counter).\(safeExt)"
            counter += 1
        }
        try data.write(to: dir.appendingPathComponent(name))
        return "assets/\(name)"
    }

    public func createFolder(named name: String, in folder: URL) async throws -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let target = uniquePath(base: safe, ext: "", in: folder)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    public func rename(at url: URL, to newName: String) async throws -> URL {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var base = newName.trimmingCharacters(in: .whitespaces)
        if !isDir { base = base.withoutMDExtension }
        let safe = base.replacingOccurrences(of: "/", with: "-")
        guard !safe.isEmpty else { return url }
        let target = url.deletingLastPathComponent().appendingPathComponent(isDir ? safe : "\(safe).md")
        if target.path == url.path { return url }
        if fm.fileExists(atPath: target.path) {
            throw NSError(domain: "Sage.Vault", code: 3, userInfo: [NSLocalizedDescriptionKey: "Имя уже занято"])
        }
        try fm.moveItem(at: url, to: target)
        return target
    }

    public func deleteNote(at url: URL) async throws {
        try fm.trashItem(at: url, resultingItemURL: nil)
    }

    public func moveNote(at url: URL, to folder: URL) async throws {
        let target = folder.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: target.path) {
            throw NSError(domain: "Sage.Vault", code: 2, userInfo: [NSLocalizedDescriptionKey: "Файл уже существует"])
        }
        try fm.moveItem(at: url, to: target)
    }

    public func allMarkdownFiles(under root: URL) async -> [URL] {
        var result: [URL] = []
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            result.append(url)
        }
        return result
    }

    /// Прямые под-папки (shallow). Раньше резолв путей строил ПОЛНОЕ рекурсивное дерево поддерева
    /// (`buildTree`) лишь чтобы прочитать прямых детей — на больших папках это дорого.
    public func childDirectories(at url: URL) async -> [URL] {
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
