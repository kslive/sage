import CoreKit
import Foundation
import MarkdownService
import SageTestSupport
import XCTest
@testable import SearchFeature

@MainActor
final class SearchViewModelTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/v")

    private func makeVault(_ files: [(String, String)]) -> MockVaultServicing {
        let v = MockVaultServicing()
        var urls: [URL] = []
        for (name, text) in files {
            let url = root.appendingPathComponent(name)
            urls.append(url)
            v.docs[url.path] = NoteDocument(url: url, text: text, modifiedAt: Date())
        }
        v.mdFiles = urls
        return v
    }

    private func wait(_ cond: @escaping () -> Bool, _ timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testLoadRecentLimitsToSix() async {
        let files = (0 ..< 10).map { ("note\($0).md", "text") }
        let vm = SearchViewModel(vault: makeVault(files), markdown: MarkdownService(), rootURL: root)
        await vm.loadRecent()
        XCTAssertEqual(vm.recent.count, 6)
    }

    func testSearchFindsContentMatch() async {
        let vault = makeVault([("a.md", "all about git and commits"), ("b.md", "cooking recipes")])
        let vm = SearchViewModel(vault: vault, markdown: MarkdownService(), rootURL: root)
        vm.query = "git"
        vm.onQueryChange()
        await wait { !vm.loading && !vm.results.isEmpty }
        XCTAssertTrue(vm.results.contains { $0.title == "a" })
        XCTAssertFalse(vm.results.contains { $0.title == "b" })
    }

    func testSearchFindsTitleMatch() async {
        let vault = makeVault([("Roadmap.md", "no keyword here")])
        let vm = SearchViewModel(vault: vault, markdown: MarkdownService(), rootURL: root)
        vm.query = "roadmap"
        vm.onQueryChange()
        await wait { !vm.loading && !vm.results.isEmpty }
        XCTAssertEqual(vm.results.first?.title, "Roadmap")
    }

    func testEmptyQueryClearsResults() async {
        let vm = SearchViewModel(vault: makeVault([("a.md", "x")]), markdown: MarkdownService(), rootURL: root)
        vm.query = "x"; vm.onQueryChange()
        await wait { !vm.results.isEmpty }
        vm.query = ""; vm.onQueryChange()
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.loading)
    }

    func testIsEmptyState() async {
        let vm = SearchViewModel(vault: makeVault([("a.md", "nothing")]), markdown: MarkdownService(), rootURL: root)
        vm.query = "zzzzz"
        vm.onQueryChange()
        await wait { !vm.loading }
        XCTAssertTrue(vm.isEmpty)
    }
}
