import CoreKit
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Локальный инференс LLM на MLX (Apple Silicon), со стримингом токенов.
/// Модель — MLX-репозиторий, уже скачанный в локальную папку (ModelService/Hub).
public actor InferenceService: Inferencing {
    private var container: ModelContainer?
    private var loadedURL: URL?
    private var contextLimit = 8192
    private var maxKV = 4096
    private var didSetMemoryLimits = false

    private var generating = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Отложенная выгрузка модели по простою (см. `scheduleIdleUnload`).
    private var unloadTask: Task<Void, Never>?

    private func acquire() async {
        unloadTask?.cancel()
        if !generating { generating = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty {
            generating = false
            /// Вернуть буферный кэш MLX (до cacheLimit ~256 МБ) сразу после ответа,
            /// не дожидаясь idle-выгрузки весов.
            MLX.GPU.clearCache()
            scheduleIdleUnload()
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Выгрузка модели после простоя: веса (4-5 ГБ Metal-буферов для 8B) не должны жить в памяти,
    /// когда ИИ не используется. Грейс 60 с — follow-up в живом диалоге не платит перезагрузку;
    /// следующий запрос после выгрузки перезагрузит модель через `load()` (~2-5 с, виден «думает»).
    private func scheduleIdleUnload() {
        unloadTask?.cancel()
        unloadTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        guard !generating, waiters.isEmpty, container != nil else { return }
        container = nil
        MLX.GPU.clearCache()
    }

    public init() {}

    public func isLoaded() async -> Bool { container != nil }

    /// Ограничиваем буферный кэш MLX, чтобы длинный промпт + 8B-модель не выедали всю память
    /// (иначе MLX/Metal падал на втором запросе).
    private func applyMemoryLimits() {
        guard !didSetMemoryLimits else { return }
        didSetMemoryLimits = true
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
    }

    public func load(modelURL: URL, template: PromptTemplate, contextSize: Int) async throws {
        applyMemoryLimits()
        unloadTask?.cancel()
        let limits = InferenceLimits(contextSize: contextSize)
        contextLimit = limits.context
        maxKV = limits.maxKV
        if loadedURL == modelURL, container != nil { return }
        do {
            container = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(directory: modelURL))
            loadedURL = modelURL
            scheduleIdleUnload()
        } catch {
            container = nil
            throw InferenceError.loadFailed
        }
    }

    /// Пересоздать контейнер из той же папки (ретрай после пустого ответа).
    public func reload() async {
        guard let url = loadedURL else { return }
        container = nil
        container = try? await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(directory: url))
    }

    public nonisolated func stream(_ request: InferenceRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(request, into: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: InferenceRequest, into continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        await acquire()
        defer { release() }
        guard let container else {
            continuation.finish(throwing: InferenceError.notLoaded)
            return
        }
        let temp = Float(max(0.05, request.temperature))
        let system = request.system
        let user = request.user + "\n\n/no_think"
        let params = GenerateParameters(
            maxTokens: 1024, maxKVSize: maxKV, kvBits: 8, quantizedKVStart: 256,
            temperature: temp, topP: 0.95)

        let produced = (try? await generateOnce(container: container, system: system, user: user, params: params, into: continuation)) ?? false
        if !produced, !Task.isCancelled {
            await reload()
            if let c = self.container {
                _ = try? await generateOnce(container: c, system: system, user: user, params: params, into: continuation)
            }
        }
        continuation.finish()
    }

    private func generateOnce(
        container: ModelContainer, system: String, user: String,
        params: GenerateParameters,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws -> Bool {
        try await container.perform { (ctx: ModelContext) -> Bool in
            let input = try await ctx.processor.prepare(input: UserInput(chat: [
                .system(system), .user(user),
            ]))
            var detok = NaiveStreamingDetokenizer(tokenizer: ctx.tokenizer)
            var produced = false
            var stripper = ThinkStripper()
            _ = try MLXLMCommon.generate(input: input, parameters: params, context: ctx) { tokens in
                if Task.isCancelled { return .stop }
                guard let last = tokens.last else { return .more }
                detok.append(token: last)
                guard let piece = detok.next(), !piece.isEmpty else { return .more }
                if let out = stripper.push(piece) {
                    produced = true
                    continuation.yield(out)
                }
                return .more
            }
            return produced
        }
    }

    public func cancel() async {}
}

public enum InferenceError: LocalizedError {
    case notLoaded
    case loadFailed

    public var errorDescription: String? {
        switch self {
        case .notLoaded: "Модель не загружена"
        case .loadFailed: "Не удалось загрузить модель"
        }
    }
}
