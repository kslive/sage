import Foundation
import XCTest
@testable import CoreKit

final class AccentPresetTests: XCTestCase {
    func testPresetByIdResolves() {
        XCTAssertEqual(AccentPreset.preset(id: "blue"), .blue)
        XCTAssertEqual(AccentPreset.preset(id: "coral"), .coral)
    }

    func testPresetUnknownFallsBackToGreen() {
        XCTAssertEqual(AccentPreset.preset(id: "несуществует"), .green)
        XCTAssertEqual(AccentPreset.preset(id: ""), .green)
    }

    func testAllPresetsDistinctWithHexes() {
        let all = AccentPreset.all
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(Set(all.map(\.id)).count, 5)                 // id уникальны
        for p in all {
            XCTAssertTrue(p.darkHex.hasPrefix("#"))
            XCTAssertTrue(p.lightHex.hasPrefix("#"))
        }
    }
}
