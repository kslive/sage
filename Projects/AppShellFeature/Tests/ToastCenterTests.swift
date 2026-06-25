import CoreKit
import XCTest
@testable import AppShellFeature

@MainActor
final class ToastCenterTests: XCTestCase {
    func testShowSetsCurrent() {
        let center = ToastCenter()
        XCTAssertNil(center.current)
        let toast = Toast(icon: "✓", text: "Готово", kind: .success)
        center.show(toast)
        XCTAssertEqual(center.current, toast)
    }

    func testSuccessAndErrorHelpers() {
        let center = ToastCenter()
        center.success("✓", "ок")
        XCTAssertEqual(center.current?.kind, .success)
        center.error("⚠️", "ошибка")
        XCTAssertEqual(center.current?.kind, .error)
        XCTAssertEqual(center.current?.text, "ошибка")
    }

    func testDismissClearsCurrent() {
        let center = ToastCenter()
        center.show(Toast(icon: "i", text: "t"))
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testShowReplacesPrevious() {
        let center = ToastCenter()
        center.show(Toast(icon: "1", text: "первый"))
        center.show(Toast(icon: "2", text: "второй"))
        XCTAssertEqual(center.current?.text, "второй")
    }

    // MARK: - subtitle (mono-путь actionable-карты)

    func testSubtitleDefaultsNil() {
        XCTAssertNil(Toast(icon: "i", text: "t").subtitle)
    }

    func testSubtitleStoredAndEquatable() {
        let a = Toast(icon: "✦", text: "Sage ответил", subtitle: "Daily/2026-06-21.md", kind: .success)
        XCTAssertEqual(a.subtitle, "Daily/2026-06-21.md")
        // subtitle входит в Equatable → разный путь = разные тосты.
        let b = Toast(id: a.id, icon: "✦", text: "Sage ответил", subtitle: "Other.md", kind: .success)
        XCTAssertNotEqual(a, b)
    }
}
