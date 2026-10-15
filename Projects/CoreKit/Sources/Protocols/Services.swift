import Foundation

// MARK: - Vault

public protocol VaultServicing: Sendable {
    func buildTree(at root: URL) async throws -> FileNode
    func readNote(at url: URL) async throws -> NoteDocument
    func writeNote(_ document: NoteDocument) async throws
    func createNote(named name: String, in folder: URL) async throws -> URL
    func createNote(named name: String, content: String, in folder: URL) async throws -> URL
    func createFolder(named name: String, in folder: URL) async throws -> URL
    func deleteNote(at url: URL) async throws
    func moveNote(at url: URL, to folder: URL) async throws
    func rename(at url: URL, to newName: String) async throws -> URL
    func allMarkdownFiles(under root: URL) async -> [URL]
    /// Прямые под-папки каталога (shallow — без рекурсии всего поддерева). Для резолва путей создания папок.
    func childDirectories(at url: URL) async -> [URL]
    /// Сохранить вложение (картинку) в подпапку `assets/` рядом с заметкой. Возвращает относительный путь `assets/имя.ext`.
    func saveAsset(_ data: Data, ext: String, nearNote noteURL: URL) async throws -> String
}

// MARK: - Markdown

public protocol MarkdownRendering: Sendable {
    func render(_ markdown: String) -> [MarkdownBlock]
    func outline(_ markdown: String) -> [OutlineItem]
    func plainText(_ markdown: String) -> String
}

// MARK: - Models (каталог + загрузка)

public protocol ModelManaging: Sendable {
    func stateForLLM(_ id: String) async -> DownloadState
    func stateForWhisper(_ id: String) async -> DownloadState
    func installedLLMs() async -> [String]
    func installedWhispers() async -> [String]
    func downloadLLM(_ spec: LLMModelSpec) -> AsyncStream<DownloadState>
    func downloadWhisper(_ spec: WhisperModelSpec) -> AsyncStream<DownloadState>
    func cancel(id: String) async
    func isDownloading(_ id: String) async -> Bool
    /// Удалить скачанную модель с диска (no-op, если сейчас качается).
    func deleteLLM(_ id: String) async
    func deleteWhisper(_ id: String) async
    func localURLForLLM(_ id: String) async -> URL?
    func localURLForWhisper(_ id: String) async -> URL?
}

// MARK: - Inference (LLM)

public struct InferenceRequest: Sendable {
    public var system: String
    public var user: String
    public var temperature: Double

    public init(system: String, user: String, temperature: Double = 0.7) {
        self.system = system
        self.user = user
        self.temperature = temperature
    }
}

public protocol Inferencing: Sendable {
    func load(modelURL: URL, template: PromptTemplate, contextSize: Int) async throws
    func stream(_ request: InferenceRequest) -> AsyncThrowingStream<String, Error>
    func cancel() async
    func isLoaded() async -> Bool
    /// Немедленно выгрузить модель из памяти (no-op при активной генерации/очереди).
    func unload() async
}

// MARK: - Speech (Whisper)

public enum TranscriptionEvent: Sendable {
    case phase(VoicePhase)
    case level(Float)
    case partial(String)
    case finished(String)
    case failed(String)
}

public protocol Transcribing: Sendable {
    func requestPermission() async -> Bool
    func start(modelURL: URL, language: AppLanguage) -> AsyncStream<TranscriptionEvent>
    func stop() async
}

// MARK: - Git

public protocol GitServicing: Sendable {
    func isRepository(at url: URL) async -> Bool
    func info(at url: URL) async -> GitRepoInfo?
    func connect(remote: String, at url: URL, mergeMessage: String) async throws
    func commitAll(message: String, at url: URL) async throws -> Int
    func push(at url: URL) async throws
    func sync(at url: URL, message: String) async -> GitSyncOutcome
    func recentCommits(at url: URL, limit: Int) async -> [GitCommit]
    func disconnect(at url: URL) async
}

// MARK: - Chat history

public protocol ChatStoring: Sendable {
    func sessions() async -> [ChatSession]
    func save(_ session: ChatSession) async
    func delete(id: UUID) async
}
