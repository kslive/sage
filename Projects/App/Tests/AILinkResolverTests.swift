import CoreKit
import Foundation
import XCTest
@testable import Sage

final class AILinkResolverTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/vault")

    /// Дерево:
    /// vault/
    ///   Projects/ { roadmap.md, Картинка пример.md }
    ///   Notes/    { roadmap.md, todo.md }
    ///   A/B/ { C.md }
    ///   readme.md
    private func tree() -> FileNode {
        func file(_ rel: String) -> FileNode {
            FileNode(name: (rel as NSString).lastPathComponent, url: root.appendingPathComponent(rel), isDirectory: false, depth: 2)
        }
        func dir(_ rel: String, _ kids: [FileNode]) -> FileNode {
            FileNode(name: (rel as NSString).lastPathComponent, url: root.appendingPathComponent(rel, isDirectory: true), isDirectory: true, depth: 1, children: kids)
        }
        return FileNode(name: "vault", url: root, isDirectory: true, depth: 0, children: [
            dir("Projects", [file("Projects/roadmap.md"), file("Projects/Картинка пример.md")]),
            dir("Notes", [file("Notes/roadmap.md"), file("Notes/todo.md")]),
            dir("A", [dir("A/B", [file("A/B/C.md")])]),
            file("readme.md"),
        ])
    }

    private func resolver(current: URL? = nil) -> AILinkResolver { AILinkResolver(tree: tree(), current: current) }

    // MARK: - resolveNote

    func testResolveFullPathBeatsLeaf() {
        // "Projects/roadmap" → именно Projects/roadmap.md, НЕ Notes/roadmap.md (одинаковый leaf)
        let url = resolver().resolveNote("Projects/roadmap")
        XCTAssertEqual(url, root.appendingPathComponent("Projects/roadmap.md"))
    }

    func testResolveLeafThenFuzzy() {
        XCTAssertEqual(resolver().resolveNote("todo"), root.appendingPathComponent("Notes/todo.md"))
        // fuzzy: «картинк» (кириллический префикс) → Картинка пример.md
        XCTAssertEqual(resolver().resolveNote("картинк"), root.appendingPathComponent("Projects/Картинка пример.md"))
    }

    func testResolveAliasUsesCurrent() {
        let current = root.appendingPathComponent("open.md")
        XCTAssertEqual(resolver(current: current).resolveNote("эту заметку"), current)
        XCTAssertEqual(resolver(current: current).resolveNote("this note"), current)
    }

    func testResolveStripsAngleBracketsPercentAndMd() {
        // <Projects/Картинка пример.md> с угловыми скобками и .md → полный путь
        let want = root.appendingPathComponent("Projects/Картинка пример.md")
        XCTAssertEqual(resolver().resolveNote("<Projects/Картинка пример.md>"), want)
        // percent-кодированный пробел декодируется
        XCTAssertEqual(resolver().resolveNote("Projects/Картинка%20пример"), want)
    }

    func testResolveNestedDirVsFile() {
        XCTAssertEqual(resolver().resolveNote("A/B/C"), root.appendingPathComponent("A/B/C.md"))
    }

    func testResolveUnknownReturnsNil() {
        XCTAssertNil(resolver().resolveNote("несуществующая"))
    }

    // MARK: - findNode

    func testFindNodeBySegmentsDirAndFile() {
        let t = tree()
        XCTAssertEqual(AILinkResolver.findNode(in: t, isDir: true, name: "Notes")?.name, "Notes")
        XCTAssertEqual(AILinkResolver.findNode(in: t, isDir: false, name: "Projects/roadmap")?.name, "roadmap.md")
        XCTAssertNil(AILinkResolver.findNode(in: t, isDir: false, name: "A/B"))   // A/B — папка, не файл
    }

    // MARK: - matchingNotes

    func testMatchingNotesByFolderAndName() {
        let t = tree()
        XCTAssertEqual(Set(AILinkResolver.matchingNotes("Notes", tree: t).map(\.lastPathComponent)),
                       ["roadmap.md", "todo.md"])
        XCTAssertEqual(AILinkResolver.matchingNotes("todo", tree: t).map(\.lastPathComponent), ["todo.md"])
        // "Notes/*.md" → берётся имя папки до слэша
        XCTAssertEqual(AILinkResolver.matchingNotes("Notes/*.md", tree: t).count, 2)
    }

    // MARK: - mdPath / firstLine

    func testMdPathWrapsSpaces() {
        XCTAssertEqual(AILinkResolver.mdPath("Notes/todo.md"), "Notes/todo.md")
        XCTAssertEqual(AILinkResolver.mdPath("Моя папка/файл.md"), "<Моя папка/файл.md>")
    }

    func testFirstLineStripsMarkers() {
        XCTAssertEqual(AILinkResolver.firstLine("# Заголовок\nтело"), "Заголовок")
        XCTAssertEqual(AILinkResolver.firstLine("\n\n- пункт\nдальше"), "пункт")
        XCTAssertEqual(AILinkResolver.firstLine(""), "")
    }
}
