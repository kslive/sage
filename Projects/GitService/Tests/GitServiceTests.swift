import CoreKit
import XCTest
@testable import GitService

/// Интеграционные тесты git-логики: реальный `/usr/bin/git` + локальный bare-remote (без сети/токена).
/// Проверяют то, что было сломано до Ит.44: pull тянет апдейты, конфликт не портит репо, commit
/// работает с локальной идентичностью, connect к непустому remote подтягивает чужие заметки.
final class GitServiceTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sage-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Хелперы (raw git для подготовки сцены)

    @discardableResult
    private func git(_ args: [String], in dir: URL) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_AUTHOR_NAME"] = "Test"; env["GIT_AUTHOR_EMAIL"] = "t@e"
        env["GIT_COMMITTER_NAME"] = "Test"; env["GIT_COMMITTER_EMAIL"] = "t@e"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func dir(_ name: String) -> URL {
        let u = tmp.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func bareRemote() -> URL {
        let bare = dir("remote.git")
        git(["init", "--bare", "-b", "main"], in: bare)
        return bare
    }

    private func clone(_ bare: URL, as name: String) -> URL {
        git(["clone", bare.path, tmp.appendingPathComponent(name).path], in: tmp)
        let c = tmp.appendingPathComponent(name)
        git(["config", "user.email", "\(name)@e"], in: c)
        git(["config", "user.name", name], in: c)
        return c
    }

    private func write(_ text: String, _ file: String, in d: URL) {
        try? text.write(to: d.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    private func read(_ file: String, in d: URL) -> String {
        (try? String(contentsOf: d.appendingPathComponent(file), encoding: .utf8)) ?? ""
    }

    private func gitAvailable() -> Bool { FileManager.default.fileExists(atPath: "/usr/bin/git") }

    // MARK: - Чистые хелперы

    func testAuthedHTTPSRemote() {
        XCTAssertEqual(GitService.authedHTTPSRemote("https://github.com/u/v.git", token: "T"),
                       "https://x-access-token:T@github.com/u/v.git")
        XCTAssertNil(GitService.authedHTTPSRemote("git@github.com:u/v.git", token: "T"))     // не HTTPS (SSH)
        XCTAssertNil(GitService.authedHTTPSRemote("https://github.com/u/v.git", token: nil)) // нет токена
        XCTAssertNil(GitService.authedHTTPSRemote("https://github.com/u/v.git", token: ""))
        XCTAssertEqual(GitService.authedHTTPSRemote("https://old@github.com/u/v.git", token: "T"),
                       "https://x-access-token:T@github.com/u/v.git")                        // меняет креды
    }

    func testParseSymrefBranch() {
        XCTAssertEqual(GitService.parseSymrefBranch("ref: refs/heads/main\tHEAD\nabc123\tHEAD"), "main")
        XCTAssertEqual(GitService.parseSymrefBranch("ref: refs/heads/master\tHEAD"), "master")
        XCTAssertNil(GitService.parseSymrefBranch("abc123\tHEAD"))
        XCTAssertNil(GitService.parseSymrefBranch(""))
    }

    // MARK: - Интеграция

    /// pull реально подтягивает изменение, сделанное на другом устройстве.
    func testSyncPullsRemoteUpdates() async throws {
        try XCTSkipUnless(gitAvailable())
        let svc = GitService()
        let bare = bareRemote()
        let a = dir("a")
        write("v1\n", "note.md", in: a)
        try await svc.connect(remote: bare.path, at: a, mergeMessage: "Sage · merge · test")
        _ = await svc.sync(at: a, message: "Sage · sync · test")                       // commit v1 + push

        let b = clone(bare, as: "b")                    // другое «устройство»
        write("v1\nfrom-b\n", "note.md", in: b)
        git(["add", "-A"], in: b); git(["commit", "-m", "b edit"], in: b)
        XCTAssertEqual(git(["push", "origin", "HEAD:main"], in: b).code, 0)

        let outcome = await svc.sync(at: a, message: "Sage · sync · test")             // a синхронизируется → получает правку b
        XCTAssertEqual(read("note.md", in: a), "v1\nfrom-b\n", "pull не подтянул изменение с remote")
        if case .failed(let r) = outcome { XCTFail("sync упал: \(r)") }
    }

    /// Конфликт при rebase НЕ ломает репо: откат (abort), без маркеров в заметке, не застряло.
    func testConflictAbortsCleanly() async throws {
        try XCTSkipUnless(gitAvailable())
        let svc = GitService()
        let bare = bareRemote()
        let a = dir("a")
        write("line1\n", "note.md", in: a)
        try await svc.connect(remote: bare.path, at: a, mergeMessage: "Sage · merge · test")
        _ = await svc.sync(at: a, message: "Sage · sync · test")

        let b = clone(bare, as: "b")
        write("line1-from-b\n", "note.md", in: b)
        git(["add", "-A"], in: b); git(["commit", "-m", "b"], in: b)
        git(["push", "origin", "HEAD:main"], in: b)

        write("line1-from-a\n", "note.md", in: a)       // a правит ту же строку
        let outcome = await svc.sync(at: a, message: "Sage · sync · test")

        guard case .conflict = outcome else { return XCTFail("ожидался .conflict, получили \(outcome)") }
        XCTAssertFalse(read("note.md", in: a).contains("<<<<<<<"), "в заметку попали маркеры конфликта")
        XCTAssertEqual(read("note.md", in: a), "line1-from-a\n", "локальная версия не сохранена")
        let rebaseDir = a.appendingPathComponent(".git/rebase-merge")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rebaseDir.path), "репо застряло в mid-rebase")
    }

    /// connect к НЕпустому remote (заметки с другого устройства) → они появляются в свежем vault.
    func testConnectAdoptsRemoteNotes() async throws {
        try XCTSkipUnless(gitAvailable())
        let svc = GitService()
        let bare = bareRemote()
        let seed = clone(bare, as: "seed")              // засеять remote чужой заметкой
        write("seeded note\n", "remote-note.md", in: seed)
        git(["add", "-A"], in: seed); git(["commit", "-m", "seed"], in: seed)
        git(["push", "origin", "HEAD:main"], in: seed)

        let fresh = dir("fresh")                         // новый локальный vault (пустой)
        try await svc.connect(remote: bare.path, at: fresh, mergeMessage: "Sage · merge · test")
        XCTAssertEqual(read("remote-note.md", in: fresh), "seeded note\n", "connect не подтянул чужие заметки")
    }

    /// commit проходит благодаря локальной идентичности (без падения «Please tell me who you are»).
    func testCommitWorksWithIdentity() async throws {
        try XCTSkipUnless(gitAvailable())
        let svc = GitService()
        let bare = bareRemote()
        let a = dir("a")
        write("x\n", "n.md", in: a)
        try await svc.connect(remote: bare.path, at: a, mergeMessage: "Sage · merge · test")
        let count = try await svc.commitAll(message: "m", at: a)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(git(["log", "--oneline"], in: a).out.contains("m"))
        XCTAssertFalse(git(["config", "user.email"], in: a).out.isEmpty, "committer-идентичность не задана")
    }

    /// sync использует ПЕРЕДАННОЕ сообщение коммита (локализованное + с датой строится в UI-слое).
    func testSyncUsesProvidedCommitMessage() async throws {
        try XCTSkipUnless(gitAvailable())
        let svc = GitService()
        let bare = bareRemote()
        let a = dir("a")
        write("hello\n", "n.md", in: a)
        try await svc.connect(remote: bare.path, at: a, mergeMessage: "Sage · merge · test")
        _ = await svc.sync(at: a, message: "Sage · auto-sync · 2026-06-24 17:30")
        XCTAssertTrue(git(["log", "--oneline"], in: a).out.contains("Sage · auto-sync · 2026-06-24 17:30"),
                      "sync не использовал переданное сообщение коммита")
    }
}
