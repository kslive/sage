import Foundation

/// Минимальный OpenAI-совместимый клиент DeepSeek API (https://api.deepseek.com).
/// Опциональный облачный путь ИИ: пользователь вводит ключ в Настройках; ЛЮБАЯ ошибка
/// облака — фолбэк на локальную MLX-модель. Id моделей всегда берутся из GET /models
/// (не хардкодим — DeepSeek переименовывает/выводит их из оборота).
public enum DeepSeekClient {
    public enum ClientError: LocalizedError {
        case http(Int, String)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case let .http(code, body): "DeepSeek HTTP \(code): \(body.prefix(200))"
            case .emptyResponse: "DeepSeek вернул пустой ответ"
            }
        }
    }

    // swiftlint:disable force_unwrapping
    private static let base = URL(string: "https://api.deepseek.com")!
    // swiftlint:enable force_unwrapping

    /// Длинные таймауты: генерация большого ответа может занимать минуты на стороне сервера.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    /// Модели, доступные ЭТОМУ ключу (заодно — проверка валидности ключа).
    public static func listModels(key: String) async throws -> [String] {
        var req = URLRequest(url: base.appendingPathComponent("models"))
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
        return try decodeModels(data)
    }

    /// Один chat completion (без стриминга). Бросает на любой транспортной/HTTP/парс-ошибке —
    /// вызывающий уходит в фолбэк на локальную модель.
    public static func chat(key: String, model: String, system: String, user: String,
                            temperature: Double = 0.6, maxTokens: Int = 8000) async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        try checkHTTP(resp, data: data)
        return try decodeChat(data)
    }

    private static func checkHTTP(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(bytes: data, encoding: .utf8) ?? "")
        }
    }

    /// Вынесено для юнит-тестов (без сети).
    static func decodeModels(_ data: Data) throws -> [String] {
        try JSONDecoder().decode(DeepSeekModelsResponse.self, from: data).data.map(\.id)
    }

    static func decodeChat(_ data: Data) throws -> String {
        let text = try JSONDecoder().decode(DeepSeekChatResponse.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ClientError.emptyResponse }
        return text
    }
}

struct DeepSeekModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

struct DeepSeekChatResponse: Decodable {
    struct Message: Decodable { let content: String? }
    struct Choice: Decodable { let message: Message }
    let choices: [Choice]
}
