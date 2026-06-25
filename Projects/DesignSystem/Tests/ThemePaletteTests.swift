import CoreKit
import XCTest
@testable import DesignSystem

final class ThemePaletteTests: XCTestCase {
    func testDarkAndLightFlags() {
        XCTAssertTrue(ThemePalette.dark(accent: .green).isDark)
        XCTAssertFalse(ThemePalette.light(accent: .green).isDark)
    }

    func testEquatableSameConstructionEqual() {
        XCTAssertEqual(ThemePalette.dark(accent: .green), ThemePalette.dark(accent: .green))
        XCTAssertEqual(ThemePalette.light(accent: .blue), ThemePalette.light(accent: .blue))
    }

    func testDarkDiffersFromLight() {
        XCTAssertNotEqual(ThemePalette.dark(accent: .green), ThemePalette.light(accent: .green))
    }

    func testDifferentAccentDiffersInTokens() {
        XCTAssertNotEqual(ThemePalette.dark(accent: .green), ThemePalette.dark(accent: .blue))
        XCTAssertNotEqual(ThemePalette.light(accent: .coral), ThemePalette.light(accent: .purple))
    }

    func testAllAccentsProduceConsistentMode() {
        for accent in AccentPreset.all {
            XCTAssertTrue(ThemePalette.dark(accent: accent).isDark)
            XCTAssertFalse(ThemePalette.light(accent: accent).isDark)
        }
    }

    // MARK: - Стабильный ключ идентичности (для .id(palette.key), пересоздающего NSTextField при смене темы)

    func testKeyDiffersBetweenDarkAndLight() {
        // Корень бага: `"\(Color)"` на macOS не различим между темами. `key` обязан различаться.
        XCTAssertNotEqual(ThemePalette.dark(accent: .green).key, ThemePalette.light(accent: .green).key)
    }

    func testKeyDiffersBetweenAccents() {
        XCTAssertNotEqual(ThemePalette.dark(accent: .green).key, ThemePalette.dark(accent: .blue).key)
    }

    func testKeyStableForSameTheme() {
        XCTAssertEqual(ThemePalette.dark(accent: .green).key, ThemePalette.dark(accent: .green).key)
    }

    func testKeyEncodesModeAndAccent() {
        XCTAssertEqual(ThemePalette.dark(accent: .green).key, "d_green")
        XCTAssertEqual(ThemePalette.light(accent: .green).key, "l_green")
    }
}
