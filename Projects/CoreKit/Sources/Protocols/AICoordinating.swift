import Foundation

/// Высокоуровневый координатор ИИ: фичи (редактор/чат) зависят от него,
/// а App собирает реализацию поверх InferenceService + ModelService.
public protocol AICoordinating: Sendable {
    /// Готов ли ИИ (модель загружена/доступна).
    func isReady() async -> Bool

    /// Инлайн-действие редактора (продолжить/резюме/улучшить/спросить).
    func runEditorAction(_ action: AIAction, selection: String, document: String, userPrompt: String)
        -> AsyncThrowingStream<String, Error>

    /// Ответ в чате с учётом контекста (файл/папка/хранилище/выделение).
    /// Координатор сам строит RAG-контекст и может вызывать инструменты над хранилищем.
    func chat(history: [ChatMessage], context: ChatContext)
        -> AsyncThrowingStream<AssistantEvent, Error>
}
