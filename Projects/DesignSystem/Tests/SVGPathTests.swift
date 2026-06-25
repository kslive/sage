import SwiftUI
import XCTest
@testable import DesignSystem

final class SVGPathTests: XCTestCase {
    func testArcDrawsCircleBounds() {
        // Круг r6 с центром (8,8): два полу-дуговых сегмента → bounds ≈ (2,2)-(14,14).
        let p = SVGPath.path("M2 8a6 6 0 1 0 12 0a6 6 0 1 0 -12 0", viewBox: CGSize(width: 16, height: 16))
        let b = p.boundingRect
        XCTAssertEqual(b.minX, 2, accuracy: 0.6)
        XCTAssertEqual(b.minY, 2, accuracy: 0.6)
        XCTAssertEqual(b.maxX, 14, accuracy: 0.6)
        XCTAssertEqual(b.maxY, 14, accuracy: 0.6)
    }

    func testGlyphPathsNonEmpty() {
        // Все глифы парсятся в непустой путь (в т.ч. с дугами — folder/file/copy/panel/clock).
        let glyphs: [SageGlyph] = [.chevron, .folderClosed, .folderOpen, .fileDoc, .copy,
                                   .clock, .clockLarge, .trash, .sort, .viewList, .plus, .check, .panel]
        for g in glyphs {
            let p = SVGPath.path(g.path, viewBox: CGSize(width: g.viewBox, height: g.viewBox))
            XCTAssertFalse(p.isEmpty, "пустой путь для \(g)")
            XCTAssertGreaterThan(p.boundingRect.width, 1, "вырожденная ширина для \(g)")
        }
    }

    func testRoundedRectArcClosesNearStart() {
        // Скруглённый прямоугольник (panel) — замкнутый контур, ширина ≈ 15 (vb 18).
        let p = SVGPath.path(SageGlyph.panel.path, viewBox: CGSize(width: 18, height: 18))
        XCTAssertEqual(p.boundingRect.width, 15, accuracy: 1.0)
    }
}
