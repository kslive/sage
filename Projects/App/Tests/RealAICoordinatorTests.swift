import CoreKit
import Foundation
import Localization
import SageTestSupport
import SettingsStore
import VaultService
import XCTest
@testable import Sage

@MainActor
final class RealAICoordinatorTests: XCTestCase {
    private var temp: TempVault!
    private var inference: MockInferencing!
    private var models: MockModelManaging!
    private var vault: VaultService!
    private var settings: SettingsStore!

    override func setUp() {
        super.setUp()
        temp = TempVault()
        inference = MockInferencing()
        models = MockModelManaging()
        models.llmURL = temp.root.appendingPathComponent("model.gguf")
        vault = VaultService()
        settings = SettingsStore(defaults: UserDefaults(suiteName: "ai." + UUID().uuidString)!)
        settings.vaultPath = temp.root.path
    }

    override func tearDown() { temp.cleanup(); super.tearDown() }

    private func makeCoordinator() -> RealAICoordinator {
        RealAICoordinator(inference: inference, models: models, settings: settings,
                          locale: LocaleManager(language: .en, defaults: UserDefaults(suiteName: "l." + UUID().uuidString)!),
                          vault: vault)
    }

    private func runChat(_ text: String) async throws -> [AssistantEvent] {
        let co = makeCoordinator()
        let history = [ChatMessage(id: UUID(), role: .user, text: text, createdAt: Date())]
        return try await collect(co.chat(history: history, context: .vault))
    }

    // MARK: - Агентный цикл

    func testPlainAnswerYieldsTokens() async throws {
        inference.scripts = [["Просто ", "ответ"]]
        let events = try await runChat("привет")
        let answer = events.compactMap { if case let .token(t) = $0 { return t }; return nil }.joined()
        XCTAssertEqual(answer, "Просто ответ")
    }

    func testToolExecutionCreatesNote() async throws {
        inference.scripts = [
            [#"{"tool":"create_note","args":{"title":"FromAI"}}"#],
            ["Готово."],
        ]
        let events = try await runChat("создай заметку FromAI")
        XCTAssertTrue(events.contains { if case .action = $0 { return true }; return false })
        let files = await vault.allMarkdownFiles(under: temp.root).map(\.lastPathComponent)
        XCTAssertTrue(files.contains("FromAI.md"))
        let answer = events.compactMap { if case let .token(t) = $0 { return t }; return nil }.joined()
        XCTAssertFalse(answer.contains("\"tool\""))
        XCTAssertTrue(answer.contains("Готово"))
    }

    func testRawToolJSONNeverLeaksAsToken() async throws {
        inference.scripts = [
            [#"{"tool":"create_folder","args":{"name":"X"}}"#],
            ["done"],
        ]
        let events = try await runChat("создай папку X")
        for case let .token(t) in events {
            XCTAssertFalse(t.contains("\"tool\""), "сырой tool-JSON утёк в токен: \(t)")
        }
    }

    func testDedupSkipsRepeatedTool() async throws {
        let json = #"{"tool":"create_note","args":{"title":"Once"}}"#
        inference.scripts = [[json], [json], [json]]
        let events = try await runChat("создай заметку Once")
        let actions = events.filter { if case .action = $0 { return true }; return false }
        XCTAssertEqual(actions.count, 1, "повторный одинаковый инструмент не должен исполняться")
        let files = await vault.allMarkdownFiles(under: temp.root).map(\.lastPathComponent)
        XCTAssertEqual(files.filter { $0.hasPrefix("Once") }.count, 1)
    }

    // MARK: - runEditorAction

    func testRunEditorActionStreamsTokens() async throws {
        inference.scripts = [["улуч", "шено"]]
        let co = makeCoordinator()
        let tokens = try await collect(co.runEditorAction(.improve, selection: "текст", document: "док", userPrompt: ""))
        XCTAssertEqual(tokens.joined(), "улучшено")
    }

    // MARK: - Чистые хелперы

    func testToolSignature() {
        let co = makeCoordinator()
        XCTAssertEqual(co.toolSignature(.createNote(folder: "P", title: "N", content: nil)), "create_note|P|n")
        XCTAssertEqual(co.toolSignature(.deleteNote(target: "A")), "delete_note|a")
    }

    func testRelPath() {
        let root = URL(fileURLWithPath: "/vault")
        let file = URL(fileURLWithPath: "/vault/Notes/a.md")
        XCTAssertEqual(file.relativePath(from: root), "Notes/a.md")
    }

    func testLanguageName() {
        XCTAssertEqual(makeCoordinator().languageName, "English")
    }

    func testResolveNoteAliasAndExact() {
        let co = makeCoordinator()
        let fileURL = temp.root.appendingPathComponent("roadmap.md")
        let tree = FileNode(name: temp.root.lastPathComponent, url: temp.root, isDirectory: true, depth: 0, children: [
            FileNode(name: "roadmap.md", url: fileURL, isDirectory: false, depth: 1),
        ])
        let current = temp.root.appendingPathComponent("current.md")
        XCTAssertEqual(co.resolveNote("this note", tree: tree, current: current), current)
        XCTAssertEqual(co.resolveNote("roadmap", tree: tree, current: nil), fileURL)
    }

    func testResolveOrCreateFolderNested() async {
        let co = makeCoordinator()
        let url = await co.resolveOrCreateFolder("A/B", tree: nil, root: temp.root)
        XCTAssertEqual(url?.lastPathComponent, "B")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - small talk

    func testIsSmallTalk() {
        let co = makeCoordinator()
        XCTAssertTrue(co.isSmallTalk("привет"))
        XCTAssertTrue(co.isSmallTalk("спасибо"))
        XCTAssertTrue(co.isSmallTalk("как дела"))
        XCTAssertTrue(co.isSmallTalk("hi"))
        XCTAssertFalse(co.isSmallTalk("создай заметку про планы"))
        XCTAssertFalse(co.isSmallTalk(""))
    }

    // MARK: - treeText / currentFolderLine (делегаты mdPath/firstLine/matchingNotes)

    func testTreeTextShowsNestingAndPaths() {
        let root = URL(fileURLWithPath: "/v")
        let node = FileNode(name: "v", url: root, isDirectory: true, depth: 0, children: [
            FileNode(name: "Notes", url: root.appendingPathComponent("Notes"), isDirectory: true, depth: 1, children: [
                FileNode(name: "a.md", url: root.appendingPathComponent("Notes/a.md"), isDirectory: false, depth: 2),
            ]),
        ])
        let text = makeCoordinator().treeText(node)
        XCTAssertTrue(text.contains("📁 Notes/"))
        XCTAssertTrue(text.contains("📄 a.md"))
        XCTAssertTrue(text.contains("(path: Notes/a.md)"))
    }

    func testCurrentFolderLineByContext() {
        let co = makeCoordinator()
        XCTAssertTrue(co.currentFolderLine(.vault, root: temp.root).contains("WHOLE vault"))
        let line = co.currentFolderLine(.file(name: "a", path: temp.root.appendingPathComponent("Notes/a.md").path), root: temp.root)
        XCTAssertTrue(line.contains("CURRENT LOCATION: file Notes/a.md"))
    }

    func testStaticHelperDelegation() {
        XCTAssertEqual(RealAICoordinator.mdPath("Моя папка/f.md"), "<Моя папка/f.md>")
        XCTAssertEqual(RealAICoordinator.firstLine("# T\nbody"), "T")
    }
}
