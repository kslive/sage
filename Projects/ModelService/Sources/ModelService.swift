import CoreKit
import Foundation
import Hub

/// Потокобезопасный держатель последней реальной скорости (байт/с) от загрузчика Hub —
/// колбэк snapshot пишет, поллер прогресса читает.
private final class AtomicDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func store(_ x: Double) { lock.lock(); value = x; lock.unlock() }
    func load() -> Double { lock.lock(); defer { lock.unlock() }; return value }
}

/// Загрузчик и менеджер локальных моделей: LLM — MLX-репозитории через HuggingFace Hub,
/// Whisper — ggml `.bin` через `URLSession`.
public final class ModelService: NSObject, ModelManaging, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = ModelService()

    /// Hub для MLX-моделей: качает репозитории в `<App Support>/Sage/models/llm/models/<repoId>`.
    /// Stored (не computed): init HubApi стартует его NetworkMonitor уже при запуске приложения —
    /// к моменту первой загрузки состояние сети устоялось, и snapshot не уходит ложно в offline-ветку.
    private let llmHub = HubApi(downloadBase: ModelStorage.llmHubBase())
    private let llmLock = NSLock()
    private var llmTasks: [String: Task<Void, Never>] = [:]

    private final class Ctx {
        let modelID: String
        let dest: URL
        let expected: Int64
        let validateMagic: Bool
        var continuations: [AsyncStream<DownloadState>.Continuation]
        var lastState: DownloadState
        var startTime: Date
        var lastTime: Date
        var lastBytes: Int64
        init(modelID: String, dest: URL, expected: Int64, validateMagic: Bool, continuation: AsyncStream<DownloadState>.Continuation) {
            self.modelID = modelID
            self.dest = dest
            self.expected = expected
            self.validateMagic = validateMagic
            continuations = [continuation]
            lastState = .downloading(DownloadProgress(downloadedBytes: 0, totalBytes: expected, speedBytesPerSec: 0))
            let now = Date()
            startTime = now
            lastTime = now
            lastBytes = 0
        }

        func emit(_ state: DownloadState) {
            lastState = state
            for c in continuations { c.yield(state) }
        }

        func finishAll() {
            for c in continuations { c.finish() }
            continuations.removeAll()
        }
    }

    private let lock = NSLock()
    private var byTaskID: [Int: Ctx] = [:]
    private var taskByModel: [String: URLSessionDownloadTask] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override public init() { super.init() }

    // MARK: - ModelManaging

    public func stateForLLM(_ id: String) async -> DownloadState {
        guard let spec = ModelCatalog.llm(id: id) else { return .notInstalled }
        let dir = ModelStorage.llmModelDirectory(repoId: spec.repoId)
        return ModelStorage.isValidModelDir(dir) ? .installed : .notInstalled
    }

    public func stateForWhisper(_ id: String) async -> DownloadState {
        guard let spec = ModelCatalog.whisper(id: id) else { return .notInstalled }
        let url = ModelStorage.whisperDirectory().appendingPathComponent(spec.fileName)
        return ModelStorage.isValid(url: url, expected: spec.sizeBytes) ? .installed : .notInstalled
    }

    public func installedLLMs() async -> [String] {
        ModelCatalog.llms.filter {
            ModelStorage.isValidModelDir(ModelStorage.llmModelDirectory(repoId: $0.repoId))
        }.map(\.id)
    }

    public func installedWhispers() async -> [String] {
        ModelCatalog.whispers.filter {
            ModelStorage.isValid(url: ModelStorage.whisperDirectory().appendingPathComponent($0.fileName), expected: $0.sizeBytes)
        }.map(\.id)
    }

    public func localURLForLLM(_ id: String) async -> URL? {
        guard let spec = ModelCatalog.llm(id: id) else { return nil }
        let dir = ModelStorage.llmModelDirectory(repoId: spec.repoId)
        return ModelStorage.isValidModelDir(dir) ? dir : nil
    }

    public func localURLForWhisper(_ id: String) async -> URL? {
        guard let spec = ModelCatalog.whisper(id: id) else { return nil }
        let url = ModelStorage.whisperDirectory().appendingPathComponent(spec.fileName)
        return ModelStorage.isValid(url: url, expected: spec.sizeBytes) ? url : nil
    }

    public func downloadLLM(_ spec: LLMModelSpec) -> AsyncStream<DownloadState> {
        AsyncStream { continuation in
            let dir = ModelStorage.llmModelDirectory(repoId: spec.repoId)
            if ModelStorage.isValidModelDir(dir) {
                continuation.yield(.installed); continuation.finish(); return
            }
            continuation.yield(.downloading(DownloadProgress(downloadedBytes: 0, totalBytes: spec.sizeBytes, speedBytesPerSec: 0)))
            let hub = llmHub
            let total = spec.sizeBytes
            let speedBox = AtomicDouble()
            let task = Task { [weak self] in
                let poller = Task {
                    var lastBytes: Int64 = 0
                    var lastTime = Date()
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if Task.isCancelled { break }
                        let bytes = min(ModelStorage.directoryByteSize(at: dir), total)
                        let now = Date()
                        let dt = now.timeIntervalSince(lastTime)
                        let diskSpeed = dt > 0 ? max(0, Double(bytes - lastBytes) / dt) : 0
                        let libSpeed = speedBox.load()
                        lastBytes = bytes; lastTime = now
                        continuation.yield(.downloading(DownloadProgress(
                            downloadedBytes: bytes, totalBytes: total,
                            speedBytesPerSec: libSpeed > 0 ? libSpeed : diskSpeed)))
                    }
                }
                do {
                    let repo = Hub.Repo(id: spec.repoId, type: .models)
                    func fetch() async throws {
                        _ = try await hub.snapshot(
                            from: repo,
                            matching: ["*.safetensors", "*.json", "*.txt", "*.py", "tokenizer*", "*.tiktoken", "*.model"]
                        ) { (_: Progress, speed: Double?) in speedBox.store(speed ?? 0) }
                    }
                    do {
                        try await fetch()
                    } catch let error as HubApi.EnvironmentError {
                        /// swift-transformers 0.1.24: NetworkMonitor стартует с isConnected=false и получает
                        /// первый NWPath-апдейт асинхронно — самый первый snapshot может ложно уйти в
                        /// offline-ветку и мгновенно бросить offlineModeError на свежей машине.
                        /// Одна повторная попытка после паузы; реальный офлайн упадёт и на ней.
                        guard case .offlineModeError = error else { throw error }
                        try await Task.sleep(nanoseconds: 1_500_000_000)
                        try await fetch()
                    }
                    poller.cancel(); _ = await poller.value
                    if Task.isCancelled { continuation.finish(); return }
                    if ModelStorage.isValidModelDir(dir) {
                        continuation.yield(.installed)
                    } else {
                        continuation.yield(.failed(message: DownloadError.invalidFile.localizedDescription))
                    }
                } catch is CancellationError {
                    poller.cancel(); _ = await poller.value
                    continuation.yield(.failed(message: DownloadError.cancelled.localizedDescription))
                } catch {
                    poller.cancel(); _ = await poller.value
                    continuation.yield(.failed(message: "\(DownloadError.network.localizedDescription) — \(error.localizedDescription)"))
                }
                self?.llmLock.lock(); self?.llmTasks[spec.id] = nil; self?.llmLock.unlock()
                continuation.finish()
            }
            llmLock.lock(); llmTasks[spec.id] = task; llmLock.unlock()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func deleteLLM(_ id: String) async {
        guard let spec = ModelCatalog.llm(id: id) else { return }
        llmLock.lock(); let downloading = llmTasks[id] != nil; llmLock.unlock()
        guard !downloading else { return }
        try? FileManager.default.removeItem(at: ModelStorage.llmModelDirectory(repoId: spec.repoId))
    }

    public func deleteWhisper(_ id: String) async {
        guard let spec = ModelCatalog.whisper(id: id) else { return }
        lock.lock(); let downloading = taskByModel[id] != nil; lock.unlock()
        guard !downloading else { return }
        try? FileManager.default.removeItem(
            at: ModelStorage.whisperDirectory().appendingPathComponent(spec.fileName))
    }

    public func downloadWhisper(_ spec: WhisperModelSpec) -> AsyncStream<DownloadState> {
        makeStream(
            modelID: spec.id, url: spec.downloadURL,
            dest: ModelStorage.whisperDirectory().appendingPathComponent(spec.fileName),
            expected: spec.sizeBytes, validateMagic: false
        )
    }

    public func cancel(id: String) async {
        lock.lock()
        let task = taskByModel[id]
        taskByModel[id] = nil
        lock.unlock()
        task?.cancel()
        llmLock.lock()
        let llmTask = llmTasks[id]
        llmTasks[id] = nil
        llmLock.unlock()
        llmTask?.cancel()
    }

    /// Идёт ли сейчас загрузка модели (для переподключения UI после навигации).
    public func isDownloading(_ id: String) async -> Bool {
        lock.lock(); let urlSession = taskByModel[id] != nil; lock.unlock()
        if urlSession { return true }
        llmLock.lock(); defer { llmLock.unlock() }
        return llmTasks[id] != nil
    }

    // MARK: - Download orchestration

    private func makeStream(modelID: String, url: URL, dest: URL, expected: Int64, validateMagic: Bool) -> AsyncStream<DownloadState> {
        AsyncStream { continuation in
            if ModelStorage.isValid(url: dest, expected: expected) {
                continuation.yield(.installed)
                continuation.finish()
                return
            }
            lock.lock()
            if let existing = taskByModel[modelID], let ctx = byTaskID[existing.taskIdentifier] {
                ctx.continuations.append(continuation)
                let last = ctx.lastState
                lock.unlock()
                continuation.yield(last)
                return
            }
            let task = session.downloadTask(with: url)
            let ctx = Ctx(modelID: modelID, dest: dest, expected: expected, validateMagic: validateMagic, continuation: continuation)
            byTaskID[task.taskIdentifier] = ctx
            taskByModel[modelID] = task
            lock.unlock()
            continuation.yield(ctx.lastState)
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        lock.lock()
        guard let ctx = byTaskID[downloadTask.taskIdentifier] else { lock.unlock(); return }
        let now = Date()
        let elapsed = now.timeIntervalSince(ctx.lastTime)
        var speed: Double = 0
        if elapsed > 0.25 {
            speed = Double(totalBytesWritten - ctx.lastBytes) / elapsed
            ctx.lastBytes = totalBytesWritten
            ctx.lastTime = now
        }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : ctx.expected
        if elapsed > 0.25 {
            ctx.emit(.downloading(DownloadProgress(
                downloadedBytes: totalBytesWritten, totalBytes: total, speedBytesPerSec: speed
            )))
        }
        lock.unlock()
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        lock.lock()
        let ctx = byTaskID[downloadTask.taskIdentifier]
        ctx?.emit(.verifying)
        lock.unlock()
        guard let ctx else { return }
        let fm = FileManager.default
        let finalState: DownloadState
        do {
            if fm.fileExists(atPath: ctx.dest.path) { try fm.removeItem(at: ctx.dest) }
            try fm.moveItem(at: location, to: ctx.dest)
            let sizeOK = ModelStorage.isValid(url: ctx.dest, expected: ctx.expected)
            let magicOK = ctx.validateMagic ? ModelStorage.hasGGUFMagic(url: ctx.dest) : true
            if sizeOK, magicOK {
                finalState = .installed
            } else {
                try? fm.removeItem(at: ctx.dest)
                finalState = .failed(message: DownloadError.invalidFile.localizedDescription)
            }
        } catch {
            finalState = .failed(message: DownloadError.invalidFile.localizedDescription)
        }
        lock.lock()
        ctx.emit(finalState)
        ctx.finishAll()
        byTaskID[downloadTask.taskIdentifier] = nil
        taskByModel[ctx.modelID] = nil
        lock.unlock()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        guard let ctx = byTaskID[task.taskIdentifier] else { lock.unlock(); return }
        let nsError = error as NSError
        let msg = nsError.code == NSURLErrorCancelled
            ? DownloadError.cancelled.localizedDescription
            : DownloadError.network.localizedDescription
        ctx.emit(.failed(message: msg))
        ctx.finishAll()
        byTaskID[task.taskIdentifier] = nil
        taskByModel[ctx.modelID] = nil
        lock.unlock()
    }
}
