import CoreKit
import Foundation

/// Парсер Markdown → блоки для рендера (без внешних зависимостей).
/// Инлайн-форматирование — через `AttributedString(markdown:)`.
public struct MarkdownService: MarkdownRendering {
    public init() {}

    public func render(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ")
            blocks.append(.paragraph(inline(text)))
            paragraph.removeAll()
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index]); index += 1
                }
                blocks.append(.code(language: lang.isEmpty ? nil : lang, code: code.joined(separator: "\n")))
                index += 1
                continue
            }

            if line.isEmpty { flushParagraph(); index += 1; continue }

            if line == "---" || line == "***" || line == "___" {
                flushParagraph(); blocks.append(.divider); index += 1; continue
            }

            if let heading = parseHeading(line) {
                flushParagraph(); blocks.append(heading); index += 1; continue
            }

            if let check = parseCheck(line, sourceLine: index) {
                flushParagraph(); blocks.append(check); index += 1; continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                let depth = leadingSpaces(raw) / 2
                blocks.append(.bullet(text: inline(String(line.dropFirst(2))), depth: depth))
                index += 1; continue
            }

            if let numbered = parseNumbered(line) {
                flushParagraph(); blocks.append(numbered); index += 1; continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoteLines.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(parseQuoteBlock(quoteLines))
                continue
            }

            if line.contains("|"), index + 1 < lines.count, isSeparatorRow(lines[index + 1]) {
                flushParagraph()
                let (table, consumed) = parseTable(lines, from: index)
                blocks.append(table)
                index += consumed
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    public func outline(_ markdown: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var id = 0
        for (index, line) in markdown.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let level = headingLevel(trimmed) {
                let text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                items.append(OutlineItem(id: id, level: level, text: text, line: index))
                id += 1
            }
        }
        return items
    }

    public func plainText(_ markdown: String) -> String {
        var text = markdown
        let patterns = ["#", ">", "`", "*", "_", "- [ ]", "- [x]", "- ", "|", "---"]
        for p in patterns { text = text.replacingOccurrences(of: p, with: " ") }
        return text.replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Парсинг строк

    private func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private func parseHeading(_ line: String) -> MarkdownBlock? {
        guard let level = headingLevel(line) else { return nil }
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: inline(text))
    }

    private func parseCheck(_ line: String, sourceLine: Int) -> MarkdownBlock? {
        let lower = line.lowercased()
        if lower.hasPrefix("- [ ] ") {
            return .checkItem(checked: false, text: inline(String(line.dropFirst(6))), sourceLine: sourceLine)
        }
        if lower.hasPrefix("- [x] ") {
            return .checkItem(checked: true, text: inline(String(line.dropFirst(6))), sourceLine: sourceLine)
        }
        return nil
    }

    private func parseNumbered(_ line: String) -> MarkdownBlock? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[line.startIndex ..< dotIndex]
        guard let number = Int(prefix), line[line.index(after: dotIndex)...].first == " " else { return nil }
        let text = String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
        return .numbered(index: number, text: inline(text))
    }

    private func parseQuoteBlock(_ quoteLines: [String]) -> MarkdownBlock {
        if let first = quoteLines.first, first.hasPrefix("[!") {
            let kind = String(first.dropFirst(2).prefix { $0 != "]" })
            var rest = quoteLines
            let firstClean = String(first.drop(while: { $0 != "]" }).dropFirst()).trimmingCharacters(in: .whitespaces)
            rest[0] = firstClean
            return .callout(kind: kind, text: inline(rest.filter { !$0.isEmpty }.joined(separator: " ")))
        }
        return .quote(inline(quoteLines.joined(separator: " ")))
    }

    private func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private func parseTable(_ lines: [String], from start: Int) -> (MarkdownBlock, Int) {
        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let headers = cells(lines[start]).map { inline($0) }
        var rows: [[AttributedString]] = []
        var index = start + 2
        while index < lines.count, lines[index].contains("|") {
            rows.append(cells(lines[index]).map { inline($0) })
            index += 1
        }
        return (.table(headers: headers, rows: rows), index - start)
    }

    private func leadingSpaces(_ s: String) -> Int {
        s.prefix { $0 == " " }.count
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let prepared = Self.wrapSpacedLinkURLs(text)
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(text)
    }

    /// Markdown-ссылки с пробелом в URL (`[t](Helpers/A B.md)`) — невалидный CommonMark: `AttributedString`
    /// бросает и весь абзац рендерится сырым. Оборачиваем такой URL в угловые скобки (`[t](<Helpers/A B.md>)`),
    /// тогда ссылка и абзац парсятся. Не трогаем URL без пробела и уже-в-`<>`. Чистая фн (тест). [[editor-source]]
    static func wrapSpacedLinkURLs(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\]\(([^)<>\n]*\s[^)<>\n]*)\)"#,
            with: "](<$1>)",
            options: .regularExpression
        )
    }
}
