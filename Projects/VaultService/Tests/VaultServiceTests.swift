import CoreKit
import Foundation
import SageTestSupport
import XCTest
@testable import VaultService

final class VaultServiceTests: XCTestCase {
    private var temp: TempVault!
    private var vault: VaultService!
    private var fm: FileManager { .default }

    override func setUp() {
        super.setUp()
        temp = TempVault()
        vault = VaultService()
    }

    override func tearDown() {
        temp.cleanup()
        super.tearDown()
    }

    // MARK: - createNote

    func testCreateNoteAddsMdAndContent() async throws {
        let url = try await vault.createNote(named: "Hello", content: "body", in: temp.root)
        XCTAssertEqual(url.lastPathComponent, "Hello.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "body")
    }

    func testCreateNoteUniqueNaming() async throws {
        let a = try await vault.createNote(named: "Note", in: temp.root)
        let b = try await vault.createNote(named: "Note", in: temp.root)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.lastPathComponent, "Note.md")
        XCTAssertEqual(b.lastPathComponent, "Note 1.md")
    }

    func testCreateNoteStripsSlash() async throws {
        let url = try await vault.createNote(named: "a/b", in: temp.root)
        XCTAssertFalse(url.lastPathComponent.contains("/"))
    }

    func testCreateNoteDefaultHeaderWhenEmpty() async throws {
        let url = try await vault.createNote(named: "Empty", in: temp.root)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Empty"))
    }

    // MARK: - createFolder

    func testCreateFolderUnique() async throws {
        let a = try await vault.createFolder(named: "F", in: temp.root)
        let b = try await vault.createFolder(named: "F", in: temp.root)
        XCTAssertNotEqual(a, b)
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: a.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - saveAsset

    func testSaveAssetCreatesAssetsAndReturnsRelative() async throws {
        let note = temp.write("Folder/note.md")
        let rel = try await vault.saveAsset(Data([1, 2, 3]), ext: "png", nearNote: note)
        XCTAssertTrue(rel.hasPrefix("assets/"))
        XCTAssertTrue(rel.hasSuffix(".png"))
        let assetURL = note.deletingLastPathComponent().appendingPathComponent(rel)
        XCTAssertTrue(fm.fileExists(atPath: assetURL.path))
    }

    func testSaveAssetCleansExtension() async throws {
        let note = temp.write("note.md")
        let dotPng = try await vault.saveAsset(Data([1]), ext: ".PNG", nearNote: note)
        XCTAssertTrue(dotPng.hasSuffix(".png"))                     // точка снята, нижний регистр
        let empty = try await vault.saveAsset(Data([2]), ext: "", nearNote: note)
        XCTAssertTrue(empty.hasSuffix(".png"))                      // пустое → png
        let spaced = try await vault.saveAsset(Data([3]), ext: " jpg ", nearNote: note)
        XCTAssertTrue(spaced.hasSuffix(".jpg"))                     // пробелы срезаны
    }

    func testSaveAssetDeduplicatesNames() async throws {
        let note = temp.write("note.md")
        var rels = Set<String>()
        for i: UInt8 in 0 ..< 3 { rels.insert(try await vault.saveAsset(Data([i]), ext: "png", nearNote: note)) }
        XCTAssertEqual(rels.count, 3, "имена ассетов уникальны (дедуп -1/-2)")
        for rel in rels {
            XCTAssertTrue(fm.fileExists(atPath: note.deletingLastPathComponent().appendingPathComponent(rel).path))
        }
    }

    // MARK: - buildTree

    func testBuildTreeHidesAssetsAndDotFolders() async throws {
        temp.write("visible.md")
        temp.write("assets/img.png", "x")
        temp.folder(".git")
        temp.folder("Sub")
        temp.write("Sub/inner.md")
        let tree = try await vault.buildTree(at: temp.root)
        let names = tree.children.map(\.name)
        XCTAssertTrue(names.contains("visible.md"))
        XCTAssertTrue(names.contains("Sub"))
        XCTAssertFalse(names.contains("assets"))
        XCTAssertFalse(names.contains(".git"))
    }

    func testBuildTreeSortsFoldersBeforeFiles() async throws {
        temp.write("z.md")
        temp.folder("A")
        let tree = try await vault.buildTree(at: temp.root)
        XCTAssertEqual(tree.children.first?.isDirectory, true)
    }

    func testBuildTreePopulatesModifiedDate() async throws {
        temp.write("note.md")
        let tree = try await vault.buildTree(at: temp.root)
        XCTAssertNotNil(tree.children.first { $0.name == "note.md" }?.modifiedAt)
    }

    /// Внешнее добавление файла (как из Finder) — после перестроения дерева он отображается
    /// И корректно встаёт по выбранной сортировке (имя / дата изменения). Папки всегда сначала.
    func testExternalAddReflectedAndSortedByMode() async throws {
        let apple = temp.write("apple.md", "a")
        temp.folder("Zeta")
        setMtime(apple, Date(timeIntervalSince1970: 1000))
        // «Из Finder» добавили новый файл с более свежей датой.
        let zebra = temp.write("zebra.md", "z")
        setMtime(zebra, Date(timeIntervalSince1970: 9000))

        let tree = try await vault.buildTree(at: temp.root)
        let names = tree.children.map(\.name)
        XCTAssertTrue(names.contains("zebra.md"), "новый файл отобразился после перестроения")
        XCTAssertTrue(names.contains("Zeta"))

        // По имени: папки сначала, файлы А–Я.
        XCTAssertEqual(sortedFileNodes(tree.children, by: .name).map(\.name), ["Zeta", "apple.md", "zebra.md"])
        // По дате изменения: папка впереди, файлы новые сверху → zebra перед apple.
        let byMod = sortedFileNodes(tree.children, by: .modified).map(\.name)
        XCTAssertEqual(byMod.first, "Zeta")
        XCTAssertEqual(Array(byMod.suffix(2)), ["zebra.md", "apple.md"])
    }

    private func setMtime(_ url: URL, _ date: Date) {
        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: - rename / move / delete

    func testRenameFile() async throws {
        let url = try await vault.createNote(named: "Old", in: temp.root)
        let renamed = try await vault.rename(at: url, to: "New")
        XCTAssertEqual(renamed.lastPathComponent, "New.md")
        XCTAssertTrue(fm.fileExists(atPath: renamed.path))
        XCTAssertFalse(fm.fileExists(atPath: url.path))
    }

    func testMoveNote() async throws {
        let url = try await vault.createNote(named: "M", in: temp.root)
        let dest = try await vault.createFolder(named: "Dest", in: temp.root)
        try await vault.moveNote(at: url, to: dest)
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("M.md").path))
        XCTAssertFalse(fm.fileExists(atPath: url.path))
    }

    func testDeleteNoteRemovesFile() async throws {
        let url = try await vault.createNote(named: "Del", in: temp.root)
        try await vault.deleteNote(at: url)
        XCTAssertFalse(fm.fileExists(atPath: url.path))
    }

    // MARK: - allMarkdownFiles / read-write

    func testAllMarkdownFilesRecursiveOnlyMd() async throws {
        temp.write("a.md"); temp.write("Sub/b.md"); temp.write("c.txt", "x")
        let files = await vault.allMarkdownFiles(under: temp.root)
        let names = files.map(\.lastPathComponent)
        XCTAssertTrue(names.contains("a.md"))
        XCTAssertTrue(names.contains("b.md"))
        XCTAssertFalse(names.contains("c.txt"))
    }

    func testReadWriteRoundtrip() async throws {
        let url = temp.root.appendingPathComponent("rw.md")
        try await vault.writeNote(NoteDocument(url: url, text: "hello world", modifiedAt: Date()))
        let doc = try await vault.readNote(at: url)
        XCTAssertEqual(doc.text, "hello world")
    }
}
