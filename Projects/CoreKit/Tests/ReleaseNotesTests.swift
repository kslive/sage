import XCTest
@testable import CoreKit

/// Вырезание локализованной секции анонса из трёхъязычных GitHub-нотсов Sage.
final class ReleaseNotesTests: XCTestCase {
    private let body = """
    **Sage 1.0.2** — hotfix.

    🇬🇧 English · 🇷🇺 Русский · 🇨🇳 中文

    ---

    ## 🇬🇧 English

    **Fixed** — data loss.
    - bullet one

    **Updating from 1.0.0 / 1.0.1**
    Open Settings.

    **Requires:** macOS 15+.

    ---

    ## 🇷🇺 Русский

    **Исправлено** — потеря текста.
    - пункт один

    **Обновление с 1.0.0 / 1.0.1**
    Откройте Настройки.

    ---

    ## 🇨🇳 中文

    **修复** —— 文本丢失。

    **从 1.0.0 / 1.0.1 更新**
    打开设置。

    ---

    **SHA-256** `Sage-1.0.2.zip`:
    ```
    deadbeef
    ```
    """

    func testLocalizedSectionPerLanguage() {
        let ru = ReleaseNotes.localizedSection(body, language: .ru)
        XCTAssertTrue(ru.contains("Исправлено"))
        XCTAssertFalse(ru.contains("Fixed"))
        XCTAssertFalse(ru.contains("修复"))
        XCTAssertFalse(ru.contains("SHA-256"), "футер отрезан")

        let en = ReleaseNotes.localizedSection(body, language: .en)
        XCTAssertTrue(en.contains("Fixed"))
        XCTAssertFalse(en.contains("Исправлено"))

        let zh = ReleaseNotes.localizedSection(body, language: .zh)
        XCTAssertTrue(zh.contains("修复"))
    }

    /// Анонс отрезает install-хвост («Обновление с …» и дальше) — приложение уже обновилось.
    func testAnnouncementCutsInstallTail() {
        let ru = ReleaseNotes.announcement(body, language: .ru)
        XCTAssertTrue(ru.contains("Исправлено"))
        XCTAssertTrue(ru.contains("пункт один"))
        XCTAssertFalse(ru.contains("Обновление с"))
        XCTAssertFalse(ru.contains("Настройки."))

        let en = ReleaseNotes.announcement(body, language: .en)
        XCTAssertTrue(en.contains("bullet one"))
        XCTAssertFalse(en.contains("Updating from"))
        XCTAssertFalse(en.contains("Requires"))
    }

    /// Не-трёхъязычные нотсы — фолбэк на всё тело без футера.
    func testFallbackWhenNoLanguageSections() {
        let plain = "Simple notes body.\n\n---\n\nSHA footer"
        XCTAssertEqual(ReleaseNotes.localizedSection(plain, language: .ru), "Simple notes body.")
        XCTAssertEqual(ReleaseNotes.announcement(plain, language: .en), "Simple notes body.")
    }

    func testStripFooterWithoutSeparator() {
        XCTAssertEqual(ReleaseNotes.stripFooter("  just text  "), "just text")
    }
}
