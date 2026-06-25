import XCTest
@testable import AppShellFeature

/// Разделение «выбор файла» и «курсор дерева»: ровно одна активная строка (без двойной подсветки).
@MainActor
final class SidebarSelectionTests: XCTestCase {
    private func sel(_ id: String, selected: String?, cursor: String?, focused: Bool, multi: Set<String> = []) -> Bool {
        SidebarView.rowSelected(id: id, selectedFileID: selected, cursorID: cursor, treeFocused: focused, multiSel: multi)
    }

    func testMultiSelectAlwaysHighlights() {
        XCTAssertTrue(sel("a", selected: nil, cursor: nil, focused: false, multi: ["a"]))
        XCTAssertTrue(sel("a", selected: "b", cursor: "c", focused: true, multi: ["a"]))
    }

    func testUnfocusedUsesSelectedFile() {
        // Дерево не в фокусе → активна открытая заметка, курсор игнорируется.
        XCTAssertTrue(sel("a.md", selected: "a.md", cursor: "F", focused: false))
        XCTAssertFalse(sel("F", selected: "a.md", cursor: "F", focused: false))
    }

    func testFocusedUsesCursor() {
        // Дерево в фокусе → активен курсор.
        XCTAssertTrue(sel("F", selected: "a.md", cursor: "F", focused: true))
    }

    /// Регресс дефекта: навигация стрелками на ПАПКУ не оставляет вторую подсветку на открытом файле.
    func testArrowOntoFolderDoesNotDoubleHighlight() {
        let openFile = "a.md", folderUnderCursor = "F"
        // Папка под курсором — подсвечена; ранее открытый файл — НЕ подсвечен (одна активная строка).
        XCTAssertTrue(sel(folderUnderCursor, selected: openFile, cursor: folderUnderCursor, focused: true))
        XCTAssertFalse(sel(openFile, selected: openFile, cursor: folderUnderCursor, focused: true))
    }

    /// Клик по файлу: курсор и выбор совпадают → строка подсвечена.
    func testClickFileHighlights() {
        XCTAssertTrue(sel("a.md", selected: "a.md", cursor: "a.md", focused: true))
    }
}
