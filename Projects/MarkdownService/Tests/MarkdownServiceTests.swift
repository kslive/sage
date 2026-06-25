import CoreKit
import Foundation
import XCTest
@testable import MarkdownService

final class MarkdownServiceTests: XCTestCase {
    private let md = MarkdownService()

    private func plain(_ a: AttributedString) -> String { String(a.characters) }

    func testHeadings() {
        let blocks = md.render("# H1\n## H2\n### H3")
        let headings = blocks.compactMap { block -> (Int, String)? in
            if case let .heading(level, text) = block { return (level, plain(text)) }
            return nil
        }
        XCTAssertEqual(headings.count, 3)
        XCTAssertEqual(headings[0].0, 1)
        XCTAssertEqual(headings[1].0, 2)
        XCTAssertEqual(headings[2].0, 3)
    }

    func testParagraph() {
        let blocks = md.render("Just a paragraph.")
        guard case let .paragraph(text)? = blocks.first else { return XCTFail("ожидался paragraph") }
        XCTAssertEqual(plain(text), "Just a paragraph.")
    }

    func testWrapSpacedLinkURLs() {
        // URL с пробелом → оборачиваем в <>
        XCTAssertEqual(MarkdownService.wrapSpacedLinkURLs("[t](Helpers/A B.md)"), "[t](<Helpers/A B.md>)")
        // лейбл с пробелом не трогаем — оборачиваем только URL
        XCTAssertEqual(MarkdownService.wrapSpacedLinkURLs("[A B](C D.md)"), "[A B](<C D.md>)")
        // уже в <> — без изменений (нет двойной обёртки)
        XCTAssertEqual(MarkdownService.wrapSpacedLinkURLs("[t](<A B.md>)"), "[t](<A B.md>)")
        // URL без пробела — без изменений
        XCTAssertEqual(MarkdownService.wrapSpacedLinkURLs("[t](nospace.md)"), "[t](nospace.md)")
    }

    func testSpacedLinkRendersAsLinkNotRawMarkdown() {
        // Регресс: ссылка с пробелом ломала парс ВСЕГО абзаца → сырой markdown. Теперь рендерится.
        let blocks = md.render("В папке есть файл: [MeetRec Setup](Helpers/MeetRec Setup.md).")
        guard case let .paragraph(text)? = blocks.first else { return XCTFail("ожидался paragraph") }
        XCTAssertFalse(plain(text).contains("]("), "остался сырой markdown ссылки")
        XCTAssertTrue(plain(text).contains("MeetRec Setup"), "лейбл ссылки потерян")
        XCTAssertTrue(text.runs.contains { $0.link != nil }, "ссылка не распозналась (нет link-атрибута)")
    }

    func testCheckItems() {
        let blocks = md.render("- [ ] todo\n- [x] done")
        let checks = blocks.compactMap { block -> Bool? in
            if case let .checkItem(checked, _, _) = block { return checked }
            return nil
        }
        XCTAssertEqual(checks, [false, true])
    }

    func testBulletAndNumbered() {
        let bullets = md.render("- one\n- two").contains { if case .bullet = $0 { return true }; return false }
        XCTAssertTrue(bullets)
        let numbered = md.render("1. first\n2. second").contains { if case .numbered = $0 { return true }; return false }
        XCTAssertTrue(numbered)
    }

    func testQuote() {
        XCTAssertTrue(md.render("> quoted").contains { if case .quote = $0 { return true }; return false })
    }

    func testCodeBlockWithLanguage() {
        let blocks = md.render("```swift\nlet x = 1\n```")
        guard let code = blocks.first(where: { if case .code = $0 { return true }; return false }),
              case let .code(language, body) = code else { return XCTFail("ожидался code") }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(body.contains("let x = 1"))
    }

    func testCodeBlockKeepsMarkdownChars() {
        let blocks = md.render("```\n# not a heading\n- not a bullet\n```")
        let hasHeading = blocks.contains { if case .heading = $0 { return true }; return false }
        XCTAssertFalse(hasHeading)
    }

    func testTable() {
        let blocks = md.render("| A | B |\n| --- | --- |\n| 1 | 2 |")
        guard let table = blocks.first(where: { if case .table = $0 { return true }; return false }),
              case let .table(headers, rows) = table else { return XCTFail("ожидалась table") }
        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(rows.first?.count, 2)
    }

    func testDivider() {
        XCTAssertTrue(md.render("---").contains { if case .divider = $0 { return true }; return false })
    }

    func testEmptyInput() {
        XCTAssertTrue(md.render("").isEmpty)
    }

    // MARK: - outline

    func testOutlineExtractsHeadingsOnly() {
        let items = md.outline("# Title\nbody text\n## Section\nmore")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].level, 1)
        XCTAssertEqual(items[0].text, "Title")
        XCTAssertEqual(items[1].level, 2)
        XCTAssertEqual(items[1].text, "Section")
    }

    // MARK: - plainText

    func testPlainTextStripsSyntax() {
        let p = md.plainText("# Title\n- **bold** item\n> quote")
        XCTAssertFalse(p.contains("#"))
        XCTAssertFalse(p.contains(">"))
        XCTAssertTrue(p.lowercased().contains("title"))
    }

    func testPlainTextEmpty() {
        XCTAssertEqual(md.plainText(""), "")
    }

    // MARK: - корнеры блоков

    func testCalloutKind() {
        guard case let .callout(kind, text)? = md.render("> [!warning] Будь осторожен").first else {
            return XCTFail("ожидался callout")
        }
        XCTAssertEqual(kind, "warning")
        XCTAssertTrue(plain(text).contains("Будь осторожен"))
    }

    func testCheckItemSourceLine() {
        let blocks = md.render("intro\n- [ ] task")
        guard let check = blocks.first(where: { if case .checkItem = $0 { return true }; return false }),
              case let .checkItem(_, _, sourceLine) = check else { return XCTFail("ожидался checkItem") }
        XCTAssertEqual(sourceLine, 1)            // вторая строка (индекс 1) — для toggle по исходнику
    }

    func testBulletDepthNested() {
        let blocks = md.render("- top\n  - nested")
        let depths = blocks.compactMap { block -> Int? in
            if case let .bullet(_, depth) = block { return depth }
            return nil
        }
        XCTAssertEqual(depths, [0, 1])
    }

    func testNumberedKeepsIndex() {
        guard case let .numbered(index, _)? = md.render("3. третий").first else {
            return XCTFail("ожидался numbered")
        }
        XCTAssertEqual(index, 3)
    }

    func testHeadingLevels456() {
        let levels = md.render("#### H4\n##### H5\n###### H6").compactMap { block -> Int? in
            if case let .heading(level, _) = block { return level }
            return nil
        }
        XCTAssertEqual(levels, [4, 5, 6])
    }

    func testDividerVariants() {
        XCTAssertTrue(md.render("***").contains { if case .divider = $0 { return true }; return false })
        XCTAssertTrue(md.render("___").contains { if case .divider = $0 { return true }; return false })
    }

    func testTableValues() {
        guard case let .table(headers, rows)? = md.render("| A | B |\n| --- | --- |\n| 1 | 2 |")
            .first(where: { if case .table = $0 { return true }; return false }) else { return XCTFail("ожидалась table") }
        XCTAssertEqual(headers.map(plain), ["A", "B"])
        XCTAssertEqual(rows.first?.map(plain), ["1", "2"])
    }

    func testFrontmatterRendersAsDividersAndParagraph() {
        // MarkdownService не выделяет frontmatter (это делает CM6-редактор) → --- = divider.
        let blocks = md.render("---\ntitle: T\n---\nbody")
        let dividers = blocks.filter { if case .divider = $0 { return true }; return false }
        XCTAssertEqual(dividers.count, 2)
        XCTAssertTrue(blocks.contains { if case let .paragraph(t) = $0 { return plain(t).contains("title") }; return false })
    }
}
