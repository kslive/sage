import Foundation

/// Шаблон промпта для конкретного семейства моделей.
public enum PromptTemplate: String, Codable, Sendable {
    case gemma3
    case chatML

    /// Формирует полный промпт из системной и пользовательской части.
    public func format(system: String, user: String) -> String {
        switch self {
        case .gemma3:
            "<start_of_turn>user\n\(system)\n\n\(user)<end_of_turn>\n<start_of_turn>model\n"
        case .chatML:
            "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        }
    }

    public var stopTokens: [String] {
        switch self {
        case .gemma3: ["<end_of_turn>"]
        case .chatML: ["<|im_end|>", "<|endoftext|>"]
        }
    }
}

/// Производные лимиты инференса от объявленного моделью окна контекста (чистая логика — тест).
/// Контекст уважаем как есть (флор 2048). Бюджет промпта КАПАЕТСЯ на 12k токенов для ЛЮБОЙ
/// модели: без капа длинный промпт раздувал KV-кэш (prefill накапливается неквантованным)
/// на гигабайты и минуты 100% GPU — Mac лагал целиком.
public struct InferenceLimits: Equatable, Sendable {
    public let context: Int
    public let promptBudget: Int

    public init(contextSize: Int, maxGenerationTokens: Int = 1024, margin: Int = 1200) {
        let ctx = max(2048, contextSize)
        self.context = ctx
        self.promptBudget = max(2000, min(ctx - maxGenerationTokens - margin, 12000))
    }
}

/// Спецификация локальной LLM (MLX-репозиторий HuggingFace).
public struct LLMModelSpec: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let emoji: String
    /// HF-репозиторий MLX-модели, напр. "mlx-community/Qwen3-8B-4bit".
    public let repoId: String
    public let sizeBytes: Int64
    public let contextSize: Int
    public let template: PromptTemplate
    public let recommended: Bool

    public init(
        id: String, name: String, emoji: String, repoId: String,
        sizeBytes: Int64, contextSize: Int,
        template: PromptTemplate, recommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.repoId = repoId
        self.sizeBytes = sizeBytes
        self.contextSize = contextSize
        self.template = template
        self.recommended = recommended
    }
}

/// Спецификация модели Whisper (ggml `.bin`).
public struct WhisperModelSpec: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let emoji: String
    public let fileName: String
    public let downloadURL: URL
    public let sizeBytes: Int64
    public let recommended: Bool

    public init(
        id: String, name: String, emoji: String, fileName: String,
        downloadURL: URL, sizeBytes: Int64, recommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.recommended = recommended
    }
}

private func mb(_ value: Double) -> Int64 { Int64(value * 1024 * 1024) }
// swiftlint:disable force_unwrapping
private func url(_ string: String) -> URL { URL(string: string)! }
// swiftlint:enable force_unwrapping

/// Каталог доступных моделей (URL загрузки и размеры).
public enum ModelCatalog {
    private static let hfWhisper = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"

    /// Отсортировано по размеру (меньшие первыми). Существующие записи сохраняют свои репо —
    /// скачанная модель не превращается в ре-даунлод после обновления; DWQ/Instruct-обновления
    /// идут НОВЫМИ карточками (instruct-веса + дистиллированная DWQ-квантизация — ощутимо ближе
    /// к fp16-учителю при той же памяти и скорости).
    public static let llms: [LLMModelSpec] = [
        LLMModelSpec(
            id: "qwen3-1.7b-dwq", name: "Qwen3 1.7B DWQ", emoji: "⚡️",
            repoId: "mlx-community/Qwen3-1.7B-4bit-DWQ",
            sizeBytes: mb(1000), contextSize: 40960, template: .chatML
        ),
        LLMModelSpec(
            id: "qwen3-1.7b", name: "Qwen3 1.7B", emoji: "⚡️",
            repoId: "mlx-community/Qwen3-1.7B-4bit",
            sizeBytes: mb(1050), contextSize: 40960, template: .chatML
        ),
        LLMModelSpec(
            id: "qwen3-4b-2507", name: "Qwen3 4B Instruct", emoji: "🧠",
            repoId: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510",
            sizeBytes: mb(2300), contextSize: 40960, template: .chatML, recommended: true
        ),
        LLMModelSpec(
            id: "qwen3-4b", name: "Qwen3 4B", emoji: "🧠",
            repoId: "mlx-community/Qwen3-4B-4bit",
            sizeBytes: mb(2400), contextSize: 40960, template: .chatML
        ),
        LLMModelSpec(
            id: "qwen3-8b-dwq", name: "Qwen3 8B DWQ", emoji: "🦉",
            repoId: "mlx-community/Qwen3-8B-4bit-DWQ",
            sizeBytes: mb(4650), contextSize: 40960, template: .chatML
        ),
        LLMModelSpec(
            id: "qwen3-8b", name: "Qwen3 8B", emoji: "🦉",
            repoId: "mlx-community/Qwen3-8B-4bit",
            sizeBytes: mb(4700), contextSize: 40960, template: .chatML
        ),
    ]

    public static let whispers: [WhisperModelSpec] = [
        WhisperModelSpec(id: "base", name: "Whisper Base", emoji: "🎙",
                         fileName: "ggml-base.bin", downloadURL: url(hfWhisper + "ggml-base.bin"),
                         sizeBytes: mb(142), recommended: true),
        WhisperModelSpec(id: "small", name: "Whisper Small", emoji: "🎙",
                         fileName: "ggml-small.bin", downloadURL: url(hfWhisper + "ggml-small.bin"),
                         sizeBytes: mb(466)),
        WhisperModelSpec(id: "tiny", name: "Whisper Tiny", emoji: "🎙",
                         fileName: "ggml-tiny.bin", downloadURL: url(hfWhisper + "ggml-tiny.bin"),
                         sizeBytes: mb(75)),
        WhisperModelSpec(id: "large-v3-turbo", name: "Whisper Large v3 Turbo", emoji: "🎙",
                         fileName: "ggml-large-v3-turbo.bin", downloadURL: url(hfWhisper + "ggml-large-v3-turbo.bin"),
                         sizeBytes: mb(1549)),
    ]

    /// Класс размера для группировки карточек в UI. Каждая модель каталога обязана попасть
    /// РОВНО в одну группу (закреплено тестом) — иначе карточка молча исчезнет из списков.
    public enum LLMGroupKind: String, CaseIterable, Sendable { case light, standard, max }

    public static func groups() -> [(kind: LLMGroupKind, models: [LLMModelSpec])] {
        [
            (.light, llms.filter { $0.id.hasPrefix("qwen3-1.7b") }),
            (.standard, llms.filter { $0.id.hasPrefix("qwen3-4b") }),
            (.max, llms.filter { $0.id.hasPrefix("qwen3-8b") }),
        ]
    }

    public static func llm(id: String) -> LLMModelSpec? { llms.first { $0.id == id } }
    public static func whisper(id: String) -> WhisperModelSpec? { whispers.first { $0.id == id } }
    public static let defaultLLM = "qwen3-4b-2507"
    public static let defaultWhisper = "base"
}
