import CoreKit
import Foundation
import SageTestSupport
import XCTest
@testable import EditorFeature

@MainActor
final class LinkInsertViewModelTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/v")

    private func makeVault(_ paths: [String]) -> MockVaultServicing {
        let v = MockVaultServicing()
        v.mdFiles = paths.map { root.appendingPathComponent($0) }
        return v
    }
    private func makeVM(sel: String = "", current: String? = nil, paths: [String] = [],
                        vault: MockVaultServicing? = nil) -> LinkInsertViewModel {
        LinkInsertViewModel(selectedText: sel, vault: vault ?? makeVault(paths), vaultRoot: root,
                            currentFile: current.map { root.appendingPathComponent($0) })
    }

    func testTextPrefilledFromSelection() {
        XCTAssertEqual(makeVM(sel: "  выделенное  ").text, "выделенное")
    }

    func testLoadExcludesCurrentFile() async {
        let vm = makeVM(current: "Reference/a.md", paths: ["Reference/a.md", "Reference/b.md"])
        await vm.load()
        XCTAssertEqual(vm.filteredNotes.map(\.title), ["b"])
    }

    func testFilterByNameAndRelPath() async {
        let vm = makeVM(paths: ["Reference/python-shpargalka.md", "Notes/todo.md"])
        await vm.load()
        vm.query = "python"
        XCTAssertEqual(vm.filteredNotes.map(\.title), ["python-shpargalka"])
        vm.query = "notes"                  // совпадение по relPath
        XCTAssertEqual(vm.filteredNotes.map(\.title), ["todo"])
    }

    func testDuplicateNamesDistinctRelPath() async {
        let vm = makeVM(paths: ["A/note.md", "B/note.md"])
        await vm.load()
        XCTAssertEqual(Set(vm.filteredNotes.map(\.relPath)), ["A/note.md", "B/note.md"])
    }

    func testCreateSuggestion() async {
        let vm = makeVM(paths: ["existing.md"])
        await vm.load()
        XCTAssertNil(vm.createSuggestion)            // query пуст
        vm.query = "existing"
        XCTAssertNil(vm.createSuggestion)            // уже есть
        vm.query = "new note"
        XCTAssertEqual(vm.createSuggestion, "new note")
    }

    func testBuildURLLink() {
        let vm = makeVM(sel: "Текст")
        vm.url = "https://x.com"
        XCTAssertEqual(vm.buildURLLink(), "[Текст](https://x.com)")
    }

    func testBuildURLLinkEmptyTextFallsBackToQuery() {
        let vm = makeVM()
        vm.url = "https://x.com"; vm.query = "док"
        XCTAssertEqual(vm.buildURLLink(), "[док](https://x.com)")
    }

    func testNoteLink() {
        let vm = makeVM(sel: "шпаргалка")
        let u = root.appendingPathComponent("Reference/python-shpargalka.md")
        XCTAssertEqual(vm.noteLink(u), "[шпаргалка](Reference/python-shpargalka.md)")
    }

    func testCreateAndLinkUsesCurrentFolder() async {
        let vault = makeVault([])
        let vm = makeVM(current: "Daily/today.md", vault: vault)
        await vm.load()
        vm.query = "newnote"; vm.text = "ссыль"
        let link = await vm.createAndLink()
        XCTAssertEqual(link, "[ссыль](Daily/newnote.md)")
    }

    func testBuildLinkParityWithJS() {
        XCTAssertEqual(LinkInsertViewModel.buildLink(label: "Текст", dest: "Папка/Файл.md"), "[Текст](Папка/Файл.md)")
        XCTAssertEqual(LinkInsertViewModel.buildLink(label: "", dest: "p.md"), "[ссылка](p.md)")
        XCTAssertEqual(LinkInsertViewModel.buildLink(label: "[br]ackets", dest: "p"), "[brackets](p)")
        XCTAssertEqual(LinkInsertViewModel.buildLink(label: "t", dest: "Папка/Моя заметка.md"), "[t](<Папка/Моя заметка.md>)")
    }
}
