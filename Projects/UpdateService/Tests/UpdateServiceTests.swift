import CoreKit
import Foundation
import XCTest
@testable import UpdateService

final class UpdateServiceTests: XCTestCase {
    private let fm = FileManager.default

    @discardableResult
    private func run(_ argv: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - stage: распаковка zip в staging

    func testStageExtractsAppFromZip() async throws {
        let work = fm.temporaryDirectory.appendingPathComponent("ust-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // соберём фейковый Foo.app и упакуем через ditto (как реальный релиз)
        let app = work.appendingPathComponent("Foo.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "<plist/>".write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let zip = work.appendingPathComponent("Foo.zip")
        XCTAssertEqual(run(["/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path]), 0)

        let staged = try await UpdateService().stage(zipURL: zip)
        defer { try? fm.removeItem(at: staged.deletingLastPathComponent()) } // чистим PendingUpdate

        XCTAssertEqual(staged.pathExtension, "app")
        XCTAssertTrue(fm.fileExists(atPath: staged.path), "распакованный .app должен существовать в staging")
        XCTAssertTrue(fm.fileExists(atPath: staged.appendingPathComponent("Contents/Info.plist").path))
    }

    // MARK: - applyPendingOnQuit: гейтинг по UserDefaults (arm инъектирован → без реальной замены)

    func testApplyPendingClearsKeysAndArmsWhenPathExists() throws {
        let d = UserDefaults(suiteName: "ust-pending-\(UUID().uuidString)")!
        let dir = fm.temporaryDirectory.appendingPathComponent("pend-\(UUID().uuidString).app")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        d.set(dir.path, forKey: "sage.update.pending.path")
        d.set("2.0.0", forKey: "sage.update.pending.version")

        var armed: (path: String, relaunch: Bool)?
        UpdateService.applyPendingOnQuit(defaults: d, arm: { armed = ($0, $1) })

        XCTAssertEqual(armed?.path, dir.path)
        XCTAssertEqual(armed?.relaunch, false) // на выходе — без перезапуска (вступит при следующем старте)
        XCTAssertNil(d.string(forKey: "sage.update.pending.path"))
        XCTAssertNil(d.string(forKey: "sage.update.pending.version"))
    }

    func testApplyPendingNoOpWhenPathMissing() {
        let d = UserDefaults(suiteName: "ust-pending-\(UUID().uuidString)")!
        d.set("/definitely/not/here-\(UUID().uuidString).app", forKey: "sage.update.pending.path")
        d.set("2.0.0", forKey: "sage.update.pending.version")

        var armed = false
        UpdateService.applyPendingOnQuit(defaults: d, arm: { _, _ in armed = true })

        XCTAssertFalse(armed, "нет файла → ничего не применяем")
        XCTAssertEqual(d.string(forKey: "sage.update.pending.version"), "2.0.0", "ключи не трогаем")
    }
}
