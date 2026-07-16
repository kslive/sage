import Foundation
import MLXLMCommon
import Tokenizers

/// swift-transformers `AutoTokenizer`, адаптированный к протоколу `MLXLMCommon.Tokenizer`
/// (mlx-swift-lm 3.x выбросил встроенный hub/tokenizer-стек). Ручной эквивалент экспансии
/// макроса MLXHuggingFace — без макро-пакета и его HF-клиента: swift-transformers уже в
/// приложении (скачивание моделей через HubApi).
struct SageTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        var template: String?
        let jinja = directory.appendingPathComponent("chat_template.jinja")
        if let text = try? String(contentsOf: jinja, encoding: .utf8), !text.isEmpty {
            template = text
        } else if (try? upstream.applyChatTemplate(messages: [["role": "user", "content": "x"]])) == nil {
            template = Self.chatML
        }
        return TokenizerBridge(upstream, templateOverride: template)
    }

    /// Некоторые MLX-конверсии (например, 2507 DWQ-репо) полностью вырезают chat template;
    /// без него промпт деградирует в склеенный текст и модель болтает до лимита токенов.
    /// Весь каталог Sage — семейство Qwen3, поэтому корректная форма — чистый ChatML.
    private static let chatML =
        "{% for message in messages %}<|im_start|>{{ message['role'] }}\n"
            + "{{ message['content'] }}<|im_end|>\n{% endfor %}<|im_start|>assistant\n"
}

final class TokenizerBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: any Tokenizers.Tokenizer
    private let templateOverride: String?

    init(_ upstream: any Tokenizers.Tokenizer, templateOverride: String? = nil) {
        self.upstream = upstream
        self.templateOverride = templateOverride
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        let plain = messages.map { $0 as [String: Any] }
        if let templateOverride {
            return try upstream.applyChatTemplate(messages: plain, chatTemplate: templateOverride)
        }
        do {
            return try upstream.applyChatTemplate(
                messages: plain,
                tools: tools.map { $0.map { $0 as [String: Any] } },
                additionalContext: additionalContext.map { $0 as [String: Any] }
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
