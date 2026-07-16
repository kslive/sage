import CoreKit
import Foundation

// MARK: - Vault (in-memory)

public final class MockVaultServicing: VaultServicing, @unchecked Sendable {
    public var docs: [String: NoteDocument] = [:]
    public var tree: FileNode?
    public var mdFiles: [URL] = []
    public private(set) var written: [NoteDocument] = []
    public private(set) var deleted: [URL] = []
    public private(set) var savedAssets: [(Data, String)] = []
    /// Искусственная задержка readNote (нс) — для тестов гонок переключения файлов.
    public var readDelayNanos: UInt64 = 0

    public init() {}

    public func buildTree(at root: URL) async throws -> FileNode {
        tree ?? FileNode(name: root.lastPathComponent, url: root, isDirectory: true, depth: 0, children: [])
    }

    public func readNote(at url: URL) async throws -> NoteDocument {
        if readDelayNanos > 0 { try? await Task.sleep(nanoseconds: readDelayNanos) }
        return docs[url.path] ?? NoteDocument(url: url, text: "", modifiedAt: Date(timeIntervalSince1970: 0))
    }

    public func writeNote(_ document: NoteDocument) async throws {
        docs[document.url.path] = document
        written.append(document)
    }

    public func createNote(named name: String, in folder: URL) async throws -> URL {
        try await createNote(named: name, content: "", in: folder)
    }

    public func createNote(named name: String, content: String, in folder: URL) async throws -> URL {
        let base = name.hasSuffix(".md") ? name : name + ".md"
        let url = folder.appendingPathComponent(base)
        docs[url.path] = NoteDocument(url: url, text: content, modifiedAt: Date())
        return url
    }

    public func createFolder(named name: String, in folder: URL) async throws -> URL {
        folder.appendingPathComponent(name, isDirectory: true)
    }

    public func deleteNote(at url: URL) async throws {
        docs[url.path] = nil
        deleted.append(url)
    }

    public func moveNote(at url: URL, to folder: URL) async throws {}

    public func rename(at url: URL, to newName: String) async throws -> URL {
        url.deletingLastPathComponent().appendingPathComponent(newName)
    }

    public func allMarkdownFiles(under root: URL) async -> [URL] {
        mdFiles.isEmpty ? docs.keys.map { URL(fileURLWithPath: $0) } : mdFiles
    }

    public func childDirectories(at url: URL) async -> [URL] {
        func find(_ node: FileNode) -> FileNode? {
            if node.url.standardizedFileURL == url.standardizedFileURL { return node }
            for c in node.children { if let f = find(c) { return f } }
            return nil
        }
        guard let tree, let node = find(tree) else { return [] }
        return node.children.filter(\.isDirectory).map(\.url)
    }

    public func saveAsset(_ data: Data, ext: String, nearNote noteURL: URL) async throws -> String {
        savedAssets.append((data, ext))
        return "assets/mock.\(ext)"
    }
}

// MARK: - Inference (скриптованный поток токенов)

public final class MockInferencing: Inferencing, @unchecked Sendable {
    /// Очередь скриптов: один элемент на каждый вызов stream() (для многошагового агента).
    public var scripts: [[String]] = []
    /// Если очередь пуста — выдаётся этот набор токенов.
    public var fallback: [String] = []
    public var throwOnStream: Error?
    public private(set) var streamCount = 0
    public private(set) var loadCount = 0
    public private(set) var cancelCount = 0
    public private(set) var unloadCount = 0

    public init() {}

    public func load(modelURL: URL, template: PromptTemplate, contextSize: Int) async throws { loadCount += 1 }

    public func stream(_ request: InferenceRequest) -> AsyncThrowingStream<String, Error> {
        streamCount += 1
        let tokens = scripts.isEmpty ? fallback : scripts.removeFirst()
        let err = throwOnStream
        return AsyncThrowingStream { continuation in
            if let err { continuation.finish(throwing: err); return }
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }

    public func cancel() async { cancelCount += 1 }
    public func isLoaded() async -> Bool { loadCount > 0 }
    public func unload() async { unloadCount += 1 }
}

// MARK: - AICoordinating (скриптованные события)

public final class MockAICoordinating: AICoordinating, @unchecked Sendable {
    public var chatEvents: [AssistantEvent] = []
    public var editorTokens: [String] = []
    public var ready = true
    public private(set) var chatCount = 0
    public private(set) var editorCount = 0

    public init() {}

    public func isReady() async -> Bool { ready }

    public func runEditorAction(_ action: AIAction, selection: String, document: String, userPrompt: String)
        -> AsyncThrowingStream<String, Error> {
        editorCount += 1
        let tokens = editorTokens
        return AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }

    public func chat(history: [ChatMessage], context: ChatContext) -> AsyncThrowingStream<AssistantEvent, Error> {
        chatCount += 1
        let events = chatEvents
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

// MARK: - ChatStoring (in-memory)

public final class MockChatStoring: ChatStoring, @unchecked Sendable {
    public var stored: [ChatSession] = []
    public private(set) var saveCount = 0

    public init() {}

    public func sessions() async -> [ChatSession] { stored.sorted { $0.updatedAt > $1.updatedAt } }
    public func save(_ session: ChatSession) async {
        stored.removeAll { $0.id == session.id }
        stored.append(session)
        saveCount += 1
    }

    public func delete(id: UUID) async { stored.removeAll { $0.id == id } }
}

// MARK: - Models (скриптованные загрузки)

public final class MockModelManaging: ModelManaging, @unchecked Sendable {
    public var llmStates: [DownloadState] = [.installed]
    public var whisperStates: [DownloadState] = [.installed]
    /// URL, который вернёт localURLForLLM (для ensureLoaded в координаторе). nil → модель «не скачана».
    public var llmURL: URL?
    public var whisperURL: URL?
    public private(set) var llmRequested: [String] = []
    public private(set) var whisperRequested: [String] = []

    public init() {}

    public func downloadLLM(_ spec: LLMModelSpec) -> AsyncStream<DownloadState> {
        llmRequested.append(spec.id)
        return Self.stream(llmStates)
    }

    public func downloadWhisper(_ spec: WhisperModelSpec) -> AsyncStream<DownloadState> {
        whisperRequested.append(spec.id)
        return Self.stream(whisperStates)
    }

    static func stream(_ states: [DownloadState]) -> AsyncStream<DownloadState> {
        AsyncStream { continuation in
            for state in states { continuation.yield(state) }
            continuation.finish()
        }
    }

    public func stateForLLM(_ id: String) async -> DownloadState { .notInstalled }
    public func stateForWhisper(_ id: String) async -> DownloadState { .notInstalled }
    public func installedLLMs() async -> [String] { [] }
    public func installedWhispers() async -> [String] { [] }
    public func cancel(id: String) async {}
    public func isDownloading(_ id: String) async -> Bool { false }
    public private(set) var deletedLLMs: [String] = []
    public private(set) var deletedWhispers: [String] = []
    public func deleteLLM(_ id: String) async { deletedLLMs.append(id) }
    public func deleteWhisper(_ id: String) async { deletedWhispers.append(id) }
    public func localURLForLLM(_ id: String) async -> URL? { llmURL }
    public func localURLForWhisper(_ id: String) async -> URL? { whisperURL }
}

// MARK: - Готовые последовательности состояний загрузки

public enum DownloadStates {
    public static func progress(done: Int64, total: Int64, speed: Double) -> DownloadState {
        .downloading(DownloadProgress(downloadedBytes: done, totalBytes: total, speedBytesPerSec: speed))
    }

    /// Прогресс → проверка → установлено.
    public static let success: [DownloadState] = [
        progress(done: 0, total: 100, speed: 50),
        progress(done: 50, total: 100, speed: 50),
        .verifying,
        .installed,
    ]

    /// Прогресс → ошибка.
    public static let failure: [DownloadState] = [
        progress(done: 0, total: 100, speed: 50),
        .failed(message: "test error"),
    ]
}

// MARK: - Transcribing (скриптованные события)

public final class MockTranscribing: Transcribing, @unchecked Sendable {
    public var permission = true
    public var events: [TranscriptionEvent] = []
    /// Если задан — поток НЕ завершается после `events`, а ЖДЁТ `stop()`, который выдаёт
    /// `.phase(.transcribing)` + `.finished(finishedText)`. Моделирует реальный stop/cancel-флоу.
    public var finishedText: String?

    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?

    public init() {}

    public func requestPermission() async -> Bool { permission }
    public func start(modelURL: URL, language: AppLanguage) -> AsyncStream<TranscriptionEvent> {
        let events = events
        let holds = finishedText != nil
        return AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            if holds { self.continuation = continuation }
            else { continuation.finish() }
        }
    }

    public func stop() async {
        guard let cont = continuation else { return }
        cont.yield(.phase(.transcribing))
        cont.yield(.finished(finishedText ?? ""))
        cont.finish()
        continuation = nil
    }
}

// MARK: - OTA updates (скриптованный)

public final class MockUpdateServicing: UpdateServicing, @unchecked Sendable {
    public var releaseToReturn: UpdateRelease?
    public var checkError: Error?
    public var downloadEvents: [UpdateDownloadEvent] = []
    public var downloadError: Error?
    public var stageError: Error?
    public var stagedAppToReturn = URL(fileURLWithPath: "/tmp/sage-staged/Sage.app")
    public private(set) var stagedZip: URL?
    public private(set) var appliedStaged: URL?
    public private(set) var appliedRelaunch: Bool?
    public private(set) var checkCount = 0

    public init() {}

    public var notesToReturn: String?
    public var notesError: Error?
    public private(set) var notesRequestedVersion: String?

    public func checkForUpdate(repo: String, current: String, channel: UpdateChannel) async throws -> UpdateRelease? {
        checkCount += 1
        if let checkError { throw checkError }
        return releaseToReturn
    }

    public func releaseNotes(repo: String, version: String) async throws -> String? {
        notesRequestedVersion = version
        if let notesError { throw notesError }
        return notesToReturn
    }

    public func downloadAndVerify(_ release: UpdateRelease) -> AsyncThrowingStream<UpdateDownloadEvent, Error> {
        let events = downloadEvents
        let err = downloadError
        return AsyncThrowingStream { continuation in
            for e in events { continuation.yield(e) }
            if let err { continuation.finish(throwing: err) } else { continuation.finish() }
        }
    }

    public func stage(zipURL: URL) async throws -> URL {
        if let stageError { throw stageError }
        stagedZip = zipURL
        return stagedAppToReturn
    }

    public func applyOnQuit(stagedApp: URL, relaunch: Bool) {
        appliedStaged = stagedApp
        appliedRelaunch = relaunch
    }
}
