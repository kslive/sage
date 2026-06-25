import Foundation
import XCTest
@testable import ModelService

final class ModelStorageTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        dir = fm.temporaryDirectory.appendingPathComponent("ms-" + UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: dir)
        super.tearDown()
    }

    private func writeFile(_ name: String, bytes: Int) -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data(count: bytes).write(to: url)
        return url
    }

    func testIsValidMissingFile() {
        XCTAssertFalse(ModelStorage.isValid(url: dir.appendingPathComponent("nope.gguf"), expected: 1000))
    }

    func testIsValidWithinRange() {
        let url = writeFile("a.gguf", bytes: 1000)
        XCTAssertTrue(ModelStorage.isValid(url: url, expected: 1000))
        XCTAssertTrue(ModelStorage.isValid(url: url, expected: 1100))
    }

    func testIsValidOutOfRange() {
        let url = writeFile("b.gguf", bytes: 1000)
        XCTAssertFalse(ModelStorage.isValid(url: url, expected: 2000))
        XCTAssertFalse(ModelStorage.isValid(url: url, expected: 500))
    }

    func testHasGGUFMagic() {
        let good = dir.appendingPathComponent("g.gguf")
        try? (Data("GGUF".utf8) + Data(count: 16)).write(to: good)
        XCTAssertTrue(ModelStorage.hasGGUFMagic(url: good))

        let bad = dir.appendingPathComponent("x.bin")
        try? Data("XXXX1234".utf8).write(to: bad)
        XCTAssertFalse(ModelStorage.hasGGUFMagic(url: bad))
    }

    func testDirectories() {
        XCTAssertTrue(ModelStorage.llmDirectory().path.hasSuffix("models/llm"))
        XCTAssertTrue(ModelStorage.whisperDirectory().path.hasSuffix("models/whisper"))
    }

    func testDirectoryByteSizeSumsRecursively() {
        _ = writeFile("a.safetensors", bytes: 1000)
        _ = writeFile("config.json", bytes: 50)
        _ = writeFile("model.safetensors.incomplete", bytes: 400) // незавершённый файл тоже считается
        let sub = dir.appendingPathComponent("nested", isDirectory: true)
        try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try? Data(count: 200).write(to: sub.appendingPathComponent("b.bin"))
        XCTAssertEqual(ModelStorage.directoryByteSize(at: dir), 1650)
    }

    func testDirectoryByteSizeMissingDirIsZero() {
        let ghost = fm.temporaryDirectory.appendingPathComponent("nope-" + UUID().uuidString)
        XCTAssertEqual(ModelStorage.directoryByteSize(at: ghost), 0)
    }
}
