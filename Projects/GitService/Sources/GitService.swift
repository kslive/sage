import CoreKit
import Foundation

/// Git-интеграция через системный `git` (Process). Actor → операции над одним репо сериализованы
/// (нет гонок index.lock при наложении ручного и авто-sync).
public actor GitService: GitServicing {
    private let gitPath = "/usr/bin/git"

    public init() {}

    /// nonisolated: Process без общего состояния — read-only команды (log/status/remote) выполняются
    /// ПАРАЛЛЕЛЬНО долгому sync (actor сериализует только пишущие операции против гонок index.lock).
    @discardableResult
    nonisolated private func run(_ args: [String], in url: URL) -> (code: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", url.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines), err)
    }

    // MARK: - Чистые хелперы (тестируемые)

    /// HTTPS-remote с подставленным токеном (`https://x-access-token:<token>@host/path`).
    /// nil — если remote не HTTPS или токен пуст. Вынесено для юнит-теста сборки URL.
    static func authedHTTPSRemote(_ remote: String, token: String?) -> String? {
        guard remote.hasPrefix("https://"), let token, !token.isEmpty else { return nil }
        let stripped = String(remote.dropFirst("https://".count))
        let hostPath = stripped.contains("@") ? String(stripped.split(separator: "@").last ?? "") : stripped
        return "https://x-access-token:\(token)@\(hostPath)"
    }

    /// Извлекает имя ветки из вывода `git ls-remote --symref <url> HEAD`
    /// (строка `ref: refs/heads/<branch>\tHEAD`). nil — если не распознано.
    static func parseSymrefBranch(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n") where line.hasPrefix("ref:") {
            let parts = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if parts.count >= 2, parts[1].hasPrefix("refs/heads/") {
                return String(parts[1].dropFirst("refs/heads/".count))
            }
        }
        return nil
    }

    private func authedRemote(at url: URL) -> String? {
        let remote = run(["remote", "get-url", "origin"], in: url).out
        let token = SecretStore.get(account: SecretStore.gitTokenAccount(for: url.path))
            ?? SecretStore.get(account: SecretStore.gitTokenAccount)
        return Self.authedHTTPSRemote(remote, token: token)
    }

    /// URL для fetch/pull/push: authed-HTTPS (с токеном) либо именованный `origin`.
    private func transport(at url: URL) -> String { authedRemote(at: url) ?? "origin" }

    private func currentBranch(at url: URL) -> String {
        let b = run(["rev-parse", "--abbrev-ref", "HEAD"], in: url).out
        return b.isEmpty || b == "HEAD" ? "main" : b
    }

    private func hasCommits(at url: URL) -> Bool {
        run(["rev-parse", "--verify", "--quiet", "HEAD"], in: url).code == 0
    }

    private func refExists(_ ref: String, at url: URL) -> Bool {
        run(["rev-parse", "--verify", "--quiet", ref], in: url).code == 0
    }

    /// Дефолтная ветка remote: по symref HEAD, затем по трекинг-рефам origin/main|master, иначе main.
    private func remoteDefaultBranch(at url: URL, transport: String) -> String {
        let sym = run(["ls-remote", "--symref", transport, "HEAD"], in: url).out
        if let b = Self.parseSymrefBranch(sym) { return b }
        if refExists("refs/remotes/origin/main", at: url) { return "main" }
        if refExists("refs/remotes/origin/master", at: url) { return "master" }
        return "main"
    }

    /// Гарантирует committer-идентичность: если глобальный `user.email` не задан — выставить ЛОКАЛЬНО
    /// (не трогая существующую глобальную идентичность). Без этого `git commit` падает на чистой машине.
    private func ensureIdentity(at url: URL) {
        if run(["config", "user.email"], in: url).out.isEmpty {
            run(["config", "user.email", "sage@local"], in: url)
            run(["config", "user.name", "Sage"], in: url)
        }
    }

    // MARK: - API

    nonisolated public func isRepository(at url: URL) async -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], in: url).out == "true"
    }

    /// nonisolated: вкладка Git показывает remote/ветку/историю СРАЗУ при открытии,
    /// не дожидаясь стартового auto-sync (актор занят сетью на секунды).
    nonisolated public func info(at url: URL) async -> GitRepoInfo? {
        guard await isRepository(at: url) else { return nil }
        let remote = run(["remote", "get-url", "origin"], in: url).out
        let branch = run(["rev-parse", "--abbrev-ref", "HEAD"], in: url).out
        let clean = run(["status", "--porcelain"], in: url).out.isEmpty
        let lastDateRaw = run(["log", "-1", "--format=%ct"], in: url).out
        let lastSync = TimeInterval(lastDateRaw).map { Date(timeIntervalSince1970: $0) }
        return GitRepoInfo(
            remoteURL: remote.isEmpty ? "—" : remote,
            branch: branch.isEmpty ? "main" : branch,
            lastSync: lastSync,
            isClean: clean
        )
    }

    /// Подключение к remote: init (если надо) → remote → identity → fetch → подтянуть существующее
    /// содержимое (заметки с других устройств). Ветка берётся из remote (не хардкод `main`).
    public func connect(remote: String, at url: URL, mergeMessage: String) async throws {
        if !(await isRepository(at: url)) {
            run(["init"], in: url)
        }
        let existing = run(["remote"], in: url).out
        if existing.contains("origin") {
            run(["remote", "set-url", "origin", remote], in: url)
        } else {
            run(["remote", "add", "origin", remote], in: url)
        }
        ensureIdentity(at: url)

        let transport = transport(at: url)
        run(["fetch", transport, "+refs/heads/*:refs/remotes/origin/*"], in: url)

        let rb = remoteDefaultBranch(at: url, transport: transport)
        let remoteHasBranch = refExists("refs/remotes/origin/\(rb)", at: url)
        let localHasCommits = hasCommits(at: url)

        if remoteHasBranch, !localHasCommits {
            run(["checkout", "-B", rb, "refs/remotes/origin/\(rb)"], in: url)
        } else if remoteHasBranch, localHasCommits {
            run(["branch", "-M", rb], in: url)
            let merge = run(["merge", "refs/remotes/origin/\(rb)", "--allow-unrelated-histories",
                             "-m", mergeMessage], in: url)
            if merge.code != 0 {
                let file = firstConflictFile(in: url)
                run(["merge", "--abort"], in: url)
                throw GitError.connectConflict(file)
            }
        } else {
            if localHasCommits {
                run(["branch", "-M", rb], in: url)
            } else {
                run(["checkout", "-B", rb], in: url)
            }
        }
    }

    public func commitAll(message: String, at url: URL) async throws -> Int {
        ensureIdentity(at: url)
        let changed = run(["status", "--porcelain"], in: url).out
        let count = changed.isEmpty ? 0 : changed.components(separatedBy: "\n").count
        guard count > 0 else { return 0 }
        run(["add", "-A"], in: url)
        let result = run(["commit", "-m", message], in: url)
        if result.code != 0, !result.err.isEmpty { throw GitError.commitFailed(result.err) }
        return count
    }

    public func push(at url: URL) async throws {
        let br = currentBranch(at: url)
        let result: (code: Int32, out: String, err: String)
        if let authed = authedRemote(at: url) {
            result = run(["push", authed, "HEAD:\(br)"], in: url)
        } else {
            result = run(["push", "-u", "origin", br], in: url)
        }
        if result.code != 0 { throw GitError.pushFailed(result.err) }
    }

    public func sync(at url: URL, message: String) async -> GitSyncOutcome {
        guard await isRepository(at: url) else { return .noRepo }
        ensureIdentity(at: url)
        let committed = (try? await commitAll(message: message, at: url)) ?? 0
        let branch = currentBranch(at: url)
        let transport = transport(at: url)
        let remoteHasBranch = run(["ls-remote", "--heads", transport, branch], in: url).out.contains(branch)
        if remoteHasBranch {
            /// --autostash: запись, легшая на диск между commitAll и rebase (дебаунс-сейв редактора),
            /// не валит pull и не теряется — стэшится и восстанавливается после rebase.
            let pull = run(["pull", "--rebase", "--autostash", transport, branch], in: url)
            if pull.code != 0 {
                if rebaseInProgress(at: url) || hasUnmerged(at: url) {
                    let file = firstConflictFile(in: url)
                    run(["rebase", "--abort"], in: url)
                    return .conflict(file: file)
                }
                let err = pull.err.lowercased()
                if err.contains("unrelated histories") {
                    return .unrelatedHistories
                }
                return .failed(reason: shortReason(pull.err))
            }
        }
        do {
            try await push(at: url)
            return committed > 0 ? .synced(pushed: committed) : .upToDate
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private func rebaseInProgress(at url: URL) -> Bool {
        let fm = FileManager.default
        let git = url.appendingPathComponent(".git")
        return fm.fileExists(atPath: git.appendingPathComponent("rebase-merge").path)
            || fm.fileExists(atPath: git.appendingPathComponent("rebase-apply").path)
    }

    private func hasUnmerged(at url: URL) -> Bool {
        !run(["diff", "--name-only", "--diff-filter=U"], in: url).out.isEmpty
    }

    private func firstConflictFile(in url: URL) -> String {
        let out = run(["diff", "--name-only", "--diff-filter=U"], in: url).out
        let first = out.components(separatedBy: "\n").first ?? ""
        return first.isEmpty ? "?" : first
    }

    /// Короткая причина из stderr git (первая непустая строка) — для тоста.
    private func shortReason(_ err: String) -> String {
        let line = err.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let trimmed = (line ?? err).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ошибка git" : String(trimmed.prefix(120))
    }

    nonisolated public func recentCommits(at url: URL, limit: Int) async -> [GitCommit] {
        let format = "%h\u{1f}%s\u{1f}%ct"
        let out = run(["log", "-n", "\(limit)", "--format=\(format)"], in: url).out
        guard !out.isEmpty else { return [] }
        return out.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 3 else { return nil }
            let date = TimeInterval(parts[2]).map { Date(timeIntervalSince1970: $0) } ?? Date()
            return GitCommit(id: parts[0], shortHash: parts[0], message: parts[1], date: date)
        }
    }

    public func disconnect(at url: URL) async {
        run(["remote", "remove", "origin"], in: url)
    }
}

public enum GitError: LocalizedError {
    case commitFailed(String)
    case pushFailed(String)
    case connectConflict(String)

    public var errorDescription: String? {
        switch self {
        case let .commitFailed(msg): "commit: \(msg)"
        case let .pushFailed(msg): "push: \(msg)"
        case let .connectConflict(file): "merge conflict: \(file)"
        }
    }
}
