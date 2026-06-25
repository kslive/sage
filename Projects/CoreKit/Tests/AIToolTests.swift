import XCTest
@testable import CoreKit

final class AIToolTests: XCTestCase {
    // MARK: - parse: базовые инструменты

    func testParseCreateNoteFull() {
        let t = AITool.parse(from: #"{"tool":"create_note","args":{"folder":"Projects","title":"Hello","content":"Hi body"}}"#)
        XCTAssertEqual(t, .createNote(folder: "Projects", title: "Hello", content: "Hi body"))
    }

    func testParseCreateNoteWithoutContent() {
        let t = AITool.parse(from: #"{"tool":"create_note","args":{"title":"Ideas"}}"#)
        XCTAssertEqual(t, .createNote(folder: nil, title: "Ideas", content: nil))
    }

    func testParseCreateFolder() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"create_folder","args":{"name":"Archive"}}"#),
                       .createFolder(parent: nil, name: "Archive"))
    }

    func testParseDeleteNote() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"delete_note","args":{"target":"Ideas"}}"#),
                       .deleteNote(target: "Ideas"))
    }

    func testParseDeleteNotesByFolder() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"delete_notes","args":{"matching":"Notes"}}"#),
                       .deleteNotes(matching: "Notes"))
    }

    func testParseSearch() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"search_notes","args":{"query":"git"}}"#),
                       .searchNotes(query: "git"))
    }

    func testParseReadAppendEditRenameMove() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"read_note","args":{"target":"roadmap"}}"#), .readNote(target: "roadmap"))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"append_note","args":{"target":"A","content":"x"}}"#), .appendNote(target: "A", content: "x"))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"edit_note","args":{"target":"A","content":"y"}}"#), .editNote(target: "A", content: "y"))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"rename_note","args":{"target":"A","newName":"B"}}"#), .renameNote(target: "A", newName: "B"))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"move_note","args":{"target":"A","toFolder":"P"}}"#), .moveNote(target: "A", toFolder: "P"))
    }

    func testParseListFolderOptional() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"list_folder","args":{}}"#), .listFolder(folder: nil))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"list_folder","args":{"folder":"Notes"}}"#), .listFolder(folder: "Notes"))
    }

    // MARK: - parse: нормализация (устойчивость к слабым моделям)

    func testParseStripsTrailingQuestionMarkInKeys() {
        let t = AITool.parse(from: #"{"tool":"create_note","args":{"folder?":"P","title?":"N","content?":"c"}}"#)
        XCTAssertEqual(t, .createNote(folder: "P", title: "N", content: "c"))
    }

    func testParseKeySynonyms() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"create_note","args":{"name":"N","body":"c"}}"#),
                       .createNote(folder: nil, title: "N", content: "c"))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"search_notes","args":{"q":"git"}}"#), .searchNotes(query: "git"))
    }

    func testParseToolNameSynonyms() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"new_note","args":{"title":"N"}}"#), .createNote(folder: nil, title: "N", content: nil))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"make_folder","args":{"name":"A"}}"#), .createFolder(parent: nil, name: "A"))
        XCTAssertEqual(AITool.parse(from: #"{"tool":"find","args":{"query":"x"}}"#), .searchNotes(query: "x"))
    }

    func testParseUsesNameOrActionKeyForTool() {
        XCTAssertEqual(AITool.parse(from: #"{"action":"delete_note","args":{"target":"A"}}"#), .deleteNote(target: "A"))
    }

    func testParseArgsFromTopLevel() {
        XCTAssertEqual(AITool.parse(from: #"{"tool":"create_note","title":"N"}"#),
                       .createNote(folder: nil, title: "N", content: nil))
    }

    func testParseStripsMdAndSlashesFromNames() {
        let t = AITool.parse(from: #"{"tool":"read_note","args":{"target":"/Notes/roadmap.md"}}"#)
        XCTAssertEqual(t, .readNote(target: "Notes/roadmap"))
    }

    func testParseNestedFolderPathPreserved() {
        let t = AITool.parse(from: #"{"tool":"create_note","args":{"folder":"A/B/C","title":"N"}}"#)
        XCTAssertEqual(t, .createNote(folder: "A/B/C", title: "N", content: nil))
    }

    func testParseJSONEmbeddedInProse() {
        let t = AITool.parse(from: "Хорошо, создаю.\n{\"tool\":\"create_folder\",\"args\":{\"name\":\"X\"}}\nГотово.")
        XCTAssertEqual(t, .createFolder(parent: nil, name: "X"))
    }

    func testParseRejectsPlaceholderValues() {
        XCTAssertNil(AITool.parse(from: #"{"tool":"create_note","args":{"title":"<note name>"}}"#))
    }

    func testParseUnescapedNewlinesInContent() {
        let raw = "{\"tool\":\"append_note\",\"args\":{\"target\":\"A\",\"content\":\"line1\nline2\"}}"
        XCTAssertEqual(AITool.parse(from: raw), .appendNote(target: "A", content: "line1\nline2"))
    }

    func testParseMissingRequiredReturnsNil() {
        XCTAssertNil(AITool.parse(from: #"{"tool":"create_note","args":{"content":"x"}}"#))
        XCTAssertNil(AITool.parse(from: #"{"tool":"rename_note","args":{"target":"A"}}"#))
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(AITool.parse(from: "просто текст без json"))
        XCTAssertNil(AITool.parse(from: "{ не json }"))
        XCTAssertNil(AITool.parse(from: #"{"tool":"unknown_thing","args":{}}"#))
    }

    // MARK: - stripToolJSON

    func testStripRemovesToolObject() {
        let s = AITool.stripToolJSON("До. {\"tool\":\"create_note\",\"args\":{\"title\":\"N\"}} После.")
        XCTAssertFalse(s.contains("tool"))
        XCTAssertTrue(s.contains("До."))
        XCTAssertTrue(s.contains("После."))
    }

    func testStripRemovesMultiple() {
        let s = AITool.stripToolJSON("a {\"tool\":\"x\"} b {\"action\":\"y\"} c")
        XCTAssertFalse(s.contains("{"))
    }

    func testStripKeepsNonToolText() {
        let s = AITool.stripToolJSON("Обычный ответ без инструментов.")
        XCTAssertEqual(s, "Обычный ответ без инструментов.")
    }

    func testStripKeepsNonToolBraces() {
        let s = AITool.stripToolJSON(#"Тут {"foo":"bar"} остаётся"#)
        XCTAssertTrue(s.contains("foo"))
    }

    // MARK: - name

    func testToolNames() {
        XCTAssertEqual(AITool.createNote(folder: nil, title: "x", content: nil).name, "create_note")
        XCTAssertEqual(AITool.deleteNotes(matching: "x").name, "delete_notes")
        XCTAssertEqual(AITool.moveNote(target: "a", toFolder: "b").name, "move_note")
    }
}
