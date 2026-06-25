import Foundation
import XCTest
@testable import CoreKit

final class ThinkStripperTests: XCTestCase {
    /// Прогон последовательности кусков → склейка выданного (nil-куски опускаются).
    private func strip(_ pieces: [String]) -> String {
        var s = ThinkStripper()
        return pieces.compactMap { s.push($0) }.joined()
    }

    func testEmptyThinkBlockAndLeadingNewlineTrimmed() {
        XCTAssertEqual(strip(["\n<think></think>\nHello"]), "Hello")
    }

    func testNoThinkLeadingNewlineTrimmed() {
        // Недавний баг: ответ без <think> начинался с лишнего переноса сверху.
        XCTAssertEqual(strip(["\nHello world"]), "Hello world")
        XCTAssertEqual(strip(["\n", "Hello"]), "Hello")
    }

    func testSplitExactlyOnThinkClose() {
        XCTAssertEqual(strip(["<think>рассуждение", "</think>ответ"]), "ответ")
    }

    func testThinkContentNeverLeaks() {
        let out = strip(["<think>секрет</think>видно"])
        XCTAssertEqual(out, "видно")
        XCTAssertFalse(out.contains("секрет"))
    }

    func testStreamingThinkOpenCharByChar() {
        XCTAssertEqual(strip(["<", "th", "ink>", "размышление", "</think>", "готово"]), "готово")
    }

    func testInternalSpacesPreserved() {
        XCTAssertEqual(strip(["<think></think>a  b"]), "a  b")        // двойной пробел внутри сохранён
        XCTAssertEqual(strip(["<think></think>x", "  y"]), "x  y")    // пробелы после старта контента
    }

    func testPlainMultiPiece() {
        XCTAssertEqual(strip(["Hello", " world"]), "Hello world")
    }
}
