import CoreKit
import CryptoKit
import Foundation

/// Ошибки апдейтера — ТОЛЬКО типизированные кейсы (без текста). Локализуются в UI (UpdaterViewModel).
public enum UpdateError: Error {
    case badResponse
    case checksumMismatch
    case noAppInArchive
    case installFailed(String)
}

/// OTA-апдейтер: GitHub Releases → скачать .zip → сверить SHA-256 → распаковать в staging →
/// заменить /Applications/Sage.app ПОСЛЕ выхода приложения (не трогаем живой бандл) → перезапуск.
/// Свой лёгкий апдейтер (без Sparkle), совместимый с ad-hoc-подписью. Actor — сериализует операции.
public actor UpdateService: UpdateServicing {
    public init() {}

    public func checkForUpdate(repo: String, current: String, channel: UpdateChannel) async throws -> UpdateRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=20") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Sage-Updater", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw UpdateError.badResponse
        }
        let releases = try UpdateLogic.decodeGitHubReleases(data)
        return UpdateLogic.pickUpdate(from: releases, current: current, channel: channel)
    }

    public nonisolated func downloadAndVerify(_ release: UpdateRelease) -> AsyncThrowingStream<UpdateDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var expected = release.sha256
                    if expected == nil, let shaURL = release.sha256AssetURL {
                        let (d, _) = try await URLSession.shared.data(from: shaURL)
                        expected = UpdateLogic.sha256(fromNotes: String(decoding: d, as: UTF8.self))
                    }
                    let localZip = try await Self.downloadFile(from: release.downloadURL) { rec, tot in
                        continuation.yield(.progress(UpdateProgress(received: rec, total: tot)))
                    }
                    if let expected {
                        let actual = try Self.sha256Hex(ofFile: localZip)
                        guard actual == expected.lowercased() else { throw UpdateError.checksumMismatch }
                    }
                    continuation.yield(.finished(localZip))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Распаковать проверенный zip в стабильный staging (`Application Support/Sage/PendingUpdate`),
    /// снять quarantine, вернуть путь к `.app`. БАНДЛ В /Applications НЕ ТРОГАЕТСЯ (замена — при выходе).
    public func stage(zipURL: URL) async throws -> URL {
        let fm = FileManager.default
        let staging = try Self.stagingDir()
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let unzip = run(["/usr/bin/ditto", "-x", "-k", zipURL.path, staging.path])
        guard unzip.code == 0 else { throw UpdateError.installFailed("unzip: \(unzip.err)") }

        let items = (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noAppInArchive }
        _ = run(["/usr/bin/xattr", "-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Применить подготовленное обновление ПОСЛЕ выхода текущего процесса: detached-хелпер ждёт
    /// завершения приложения, заменяет `/Applications/Sage.app` копией из staging, снимает quarantine,
    /// при `relaunch` — открывает новую версию. Так живой бандл не модифицируется (безопасно на Sequoia).
    public nonisolated func applyOnQuit(stagedApp: URL, relaunch: Bool) {
        Self.arm(stagedAppPath: stagedApp.path, relaunch: relaunch)
    }

    /// Вызывается из `applicationWillTerminate`: если есть подготовленное обновление (persist в UserDefaults) —
    /// применить его при выходе (relaunch:false → вступит в силу при следующем запуске). Без инстанса актора.
    public static func applyPendingOnQuit(defaults d: UserDefaults = .standard) {
        applyPendingOnQuit(defaults: d) { arm(stagedAppPath: $0, relaunch: $1) }
    }

    /// Internal-вариант с инъекцией `arm` — для изоляции в тестах (реальный `arm` взводит detached-хелпер,
    /// который заменяет `/Applications/Sage.app` при выходе процесса — в юните недопустимо). Доступен через `@testable`.
    static func applyPendingOnQuit(defaults d: UserDefaults,
                                   arm armFn: (_ stagedAppPath: String, _ relaunch: Bool) -> Void) {
        guard let path = d.string(forKey: "sage.update.pending.path"),
              FileManager.default.fileExists(atPath: path) else { return }
        armFn(path, false)
        d.removeObject(forKey: "sage.update.pending.path")
        d.removeObject(forKey: "sage.update.pending.version")
    }

    /// Detached-хелпер: ждёт завершения текущего процесса, заменяет `/Applications/Sage.app` из staging,
    /// снимает quarantine, при `relaunch` — открывает новую версию, чистит staging.
    private static func arm(stagedAppPath src: String, relaunch: Bool) {
        let dst = "/Applications/\(CoreKit.appName).app"
        let pid = ProcessInfo.processInfo.processIdentifier
        let stagingParent = (src as NSString).deletingLastPathComponent
        let openLine = relaunch ? "/usr/bin/open \"\(dst)\"" : ""
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        rm -rf "\(dst)"
        /usr/bin/ditto "\(src)" "\(dst)"
        /usr/bin/xattr -dr com.apple.quarantine "\(dst)" 2>/dev/null
        \(openLine)
        rm -rf "\(stagingParent)"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }

    // MARK: - helpers

    static func stagingDir() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("\(CoreKit.appName)/PendingUpdate", isDirectory: true)
    }

    private func run(_ argv: [String]) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run(); p.waitUntilExit() } catch { return (-1, "", "\(error)") }
        let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (p.terminationStatus, o, e)
    }

    private static func sha256Hex(ofFile url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func downloadFile(from url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let delegate = DownloadDelegate(progress: progress, completion: cont)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: url).resume()
        }
    }
}

/// Делегат скачивания: мост `URLSessionDownloadTask` → прогресс + single-resume continuation.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64) -> Void
    private let completion: CheckedContinuation<URL, Error>
    var session: URLSession?
    private var resumed = false

    init(progress: @escaping @Sendable (Int64, Int64) -> Void, completion: CheckedContinuation<URL, Error>) {
        self.progress = progress
        self.completion = completion
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("sage-update-\(UUID().uuidString).zip")
        do { try FileManager.default.moveItem(at: location, to: dest); finish(.success(dest)) }
        catch { finish(.failure(error)) }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !resumed else { return }
        resumed = true
        session?.finishTasksAndInvalidate()
        switch result {
        case let .success(u): completion.resume(returning: u)
        case let .failure(e): completion.resume(throwing: e)
        }
    }
}
