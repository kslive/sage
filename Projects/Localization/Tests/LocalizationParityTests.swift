import CoreKit
import XCTest
@testable import Localization

final class LocalizationParityTests: XCTestCase {
    /// Рекурсивно собирает все строковые поля (с путём) из вложенных структур Strings.
    private func fields(_ value: Any, path: String = "") -> [String: String] {
        var out: [String: String] = [:]
        for child in Mirror(reflecting: value).children {
            let label = child.label ?? "?"
            let p = path.isEmpty ? label : "\(path).\(label)"
            if let s = child.value as? String {
                out[p] = s
            } else {
                out.merge(fields(child.value, path: p)) { a, _ in a }
            }
        }
        return out
    }

    func testAllFieldsNonEmpty() {
        for (lang, s) in [("ru", Strings.ru), ("en", Strings.en), ("zh", Strings.zh)] {
            let map = fields(s)
            XCTAssertGreaterThan(map.count, 50, "\(lang): подозрительно мало полей")
            for (key, value) in map {
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(lang).\(key) пустое"
                )
            }
        }
    }

    func testSameFieldSetAcrossLanguages() {
        let ru = Set(fields(Strings.ru).keys)
        let en = Set(fields(Strings.en).keys)
        let zh = Set(fields(Strings.zh).keys)
        XCTAssertEqual(ru, en, "ru и en расходятся по набору ключей")
        XCTAssertEqual(ru, zh, "ru и zh расходятся по набору ключей")
    }

    /// Статусы синхронизации локализуются (не «up to date» на англ. для не-EN). Коды → текст языка.
    func testGitSyncToastLocalizes() {
        let en = gitSyncToast(.upToDate, .en)
        XCTAssertEqual(en.text, "Up to date"); XCTAssertFalse(en.isError)
        XCTAssertEqual(gitSyncToast(.upToDate, .ru).text, "Актуально")
        XCTAssertEqual(gitSyncToast(.upToDate, .zh).text, "已是最新")
        // synced — слово на языке + число
        XCTAssertTrue(gitSyncToast(.synced(pushed: 3), .ru).text.contains("3"))
        XCTAssertTrue(gitSyncToast(.synced(pushed: 3), .en).text.hasPrefix("Pushed"))
        // ошибки → isError + локализованный текст; raw git stderr остаётся как есть
        XCTAssertTrue(gitSyncToast(.unrelatedHistories, .ru).isError)
        XCTAssertEqual(gitSyncToast(.failed(reason: "fatal: boom"), .en).text, "fatal: boom")
        XCTAssertTrue(gitSyncToast(.conflict(file: "n.md"), .zh).text.contains("n.md"))
    }
}
