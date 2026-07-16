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
            MLX.Memory.clearCache()
            scheduleIdleUnload()
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// СТРАХОВОЧНАЯ выгрузка по простою (60 с): основной путь — немедленный `unload()` от
    /// координатора после завершения работы; таймер ловит пути, где тот не был вызван.
    /// Между шагами агентного цикла таймер не успевает — шаги не платят перезагрузку.
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
        MLX.Memory.clearCache()
    }

    /// Немедленная выгрузка после завершения РАБОТЫ (весь ответ чата / инлайн-действие) —
    /// зовёт координатор. Гард не даст выгрузить модель под чужой генерацией/очередью;
    /// 60-с таймер в release() остаётся страховкой для путей, где координатор не дозвонился.
    public func unload() {
        unloadIfIdle()
    }

    public init() {}

    public func isLoaded() async -> Bool { container != nil }

    /// Ограничиваем буферный кэш MLX: без лимита MLX кэширует КАЖДЫЙ промежуточный буфер
    /// длинной генерации и не возвращает память (Apple в LLMEval ставит лимит именно поэтому).
    private func applyMemoryLimits() {
        guard !didSetMemoryLimits else { return }
        didSetMemoryLimits = true
        MLX.Memory.cacheLimit = 128 * 1024 * 1024
    }

    public func load(modelURL: URL, template: PromptTemplate, contextSize: Int) async throws {
        applyMemoryLimits()
        unloadTask?.cancel()
        let limits = InferenceLimits(contextSize: contextSize)
        contextLimit = limits.context
        if loadedURL == modelURL, container != nil { return }
        do {
            container = try await LLMModelFactory.shared.loadContainer(
                from: modelURL, using: SageTokenizerLoader())
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
            from: url, using: SageTokenizerLoader())
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
        /// БЕЗ maxKVSize: с ним KV-кэш становится ротационным, и `maybeQuantizeKVCache` пропускает
        /// его квантизацию — память хуже И контекст молча дропается. KVCacheSimple + kvBits:8
        /// держит память ограниченной без потери контекста. repetitionPenalty с ШИРОКИМ окном —
        /// то, что предотвращает зацикливание абзацев (короткое окно хуже, чем без penalty).
        var params = GenerateParameters(
            maxTokens: 1024, kvBits: 8, quantizedKVStart: 256,
            temperature: temp, topP: 0.95, prefillStepSize: 1024)
        params.repetitionPenalty = 1.1
        params.repetitionContextSize = 128

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
            var produced = false
            var stripper = ThinkStripper()
            for await generation in try MLXLMCommon.generate(input: input, parameters: params, context: ctx) {
                if Task.isCancelled { break }
                guard let piece = generation.chunk, !piece.isEmpty else { continue }
                if let out = stripper.push(piece) {
                    produced = true
                    continuation.yield(out)
                }
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
