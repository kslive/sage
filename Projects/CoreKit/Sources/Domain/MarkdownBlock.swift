import Foundation

/// Блок отрендеренного Markdown (результат `MarkdownRendering`).
/// Инлайн-форматирование (жирный/курсив/код/ссылки) — в `AttributedString`.
public enum MarkdownBlock: Identifiable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case checkItem(checked: Bool, text: AttributedString, sourceLine: Int)
    case bullet(text: AttributedString, depth: Int)
    case numbered(index: Int, text: AttributedString)
    case quote(AttributedString)
    case callout(kind: String, text: AttributedString)
    case code(language: String?, code: String)
    case table(headers: [AttributedString], rows: [[AttributedString]])
    case divider

    public var id: String {
        switch self {
        case let .heading(level, text): "h\(level)-\(text.characters.count)-\(String(text.characters.prefix(12)))"
        case let .paragraph(text): "p-\(text.characters.count)-\(String(text.characters.prefix(12)))"
        case let .checkItem(_, _, line): "chk-\(line)"
        case let .bullet(text, depth): "ul-\(depth)-\(String(text.characters.prefix(12)))"
        case let .numbered(index, text): "ol-\(index)-\(String(text.characters.prefix(12)))"
        case let .quote(text): "q-\(String(text.characters.prefix(12)))"
        case let .callout(kind, text): "cal-\(kind)-\(String(text.characters.prefix(12)))"
        case let .code(lang, code): "code-\(lang ?? "")-\(code.count)"
        case let .table(headers, rows): "tbl-\(headers.count)-\(rows.count)"
        case .divider: "hr-\(UUID().uuidString)"
        }
    }
}
