import CoreKit
import Foundation
import Observation

@MainActor
@Observable
public final class ChatViewModel {
    public var context: ChatContext
    public var messages: [ChatMessage] = []
    public var input = ""
    public var streamTick = 0
    public var isThinking = false
    public var isStreaming = false
    public var isError = false
    public var voice: VoicePhase = .off
    public var historyOpen = false
    public var sessions: [ChatSession] = []
    public var waveLevels: [Float] = Array(repeating: 0.4, count: 7)
    /// Когда началась запись голоса (для таймера mm:ss в orb-оверлее). nil вне записи.
    public private(set) var recordingStart: Date?
    public var pendingDeletion: PendingDeletion?

    public struct PendingDeletion: Equatable {
        public let path: String
        public let title: String
    }

    private var sessionID = UUID()
    private let ai: AICoordinating
    private let vault: VaultServicing
    private let speech: Transcribing
    private let store: ChatStoring
    private var whisperURL: URL?
    /// Голос доступен, если установлена whisper-модель. Вычисляемое (не замороженный let) — микрофон
    /// появляется реактивно, как только URL подгрузится, даже если VM создан раньше (keep-alive).
    public var whisperAvailable: Bool { whisperURL != nil }
    private let language: AppLanguage
    /// Воркспейс этого VM — история фильтруется по нему (не «протекает» между папками).
    private let vaultRoot: URL?
    /// Реестр фоновых задач ИИ (опц.).
    private let tasks: AITaskRegistry?

    private var streamTask: Task<Void, Never>?
    private var voiceTask: Task<Void, Never>?
    /// Набранный текст ДО старта голоса — распознанное приклеиваем к нему; отмена (×) восстанавливает его.
    private var voicePrefix = ""
    /// Подтверждение (✓/Enter) → после распознавания СРАЗУ отправить в чат (инпут не показываем).
    private var voiceAutoSend = false
    /// Поколение генерации: stop()/re-send инкрементят → терминал старой задачи не трогает реестр/стейт.
    private var aiGen = 0

    public init(
        context: ChatContext, ai: AICoordinating, vault: VaultServicing,
        speech: Transcribing, store: ChatStoring,
        whisperURL: URL?, language: AppLanguage, vaultRoot: URL? = nil,
        tasks: AITaskRegistry? = nil
    ) {
        self.context = context
        self.ai = ai
        self.vault = vault
        self.speech = speech
        self.store = store
        self.whisperURL = whisperURL
        self.language = language
        self.vaultRoot = vaultRoot
        self.tasks = tasks
    }

    /// Обновить путь whisper-модели (после асинхронной загрузки на старте/смене модели).
    /// Включает микрофон у уже живущих keep-alive VM (в т.ч. vault-чата, созданного до загрузки URL).
    public func updateWhisper(_ url: URL?) { whisperURL = url }

    /// Только сессии текущего воркспейса (legacy без vaultPath не показываем — их подчистит make reset).
    private func ownSessions(_ all: [ChatSession]) -> [ChatSession] {
        guard let vp = vaultRoot?.path else { return all }
        return all.filter { $0.vaultPath == vp }
    }

    public var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }
    public var isBusy: Bool { isThinking || isStreaming }

    /// Загрузили ли последнюю сессию контекста. Пока false — НЕ показываем пустой стейт (иначе мелькает).
    public private(set) var didLoad = false

    /// Идёт ли СЕЙЧАС async-загрузка сессии (bootstrap/switchContext). Пока true — пустой стейт НЕ показываем
    /// (иначе мелькает в окне между `messages=[]` и подгрузкой). init=true: до первого bootstrap не мелькаем.
    public private(set) var isLoadingSession = true

    /// Однократно подгрузить последнюю сессию этого контекста (idempotent — VM живёт постоянно).
    public func bootstrap() async {
        guard !didLoad else { return }
        didLoad = true
        guard messages.isEmpty else { isLoadingSession = false; return }
        let sessions = ownSessions(await store.sessions())
        if let existing = sessions.first(where: { sameContext($0.context, context) }) {
            sessionID = existing.id
            messages = existing.messages
        }
        isLoadingSession = false
    }

    /// Подставить текст и отправить (для «спросить из поиска» и т.п.).
    public func sendPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = trimmed
        send()
    }

    func sameContext(_ a: ChatContext, _ b: ChatContext) -> Bool {
        switch (a, b) {
        case (.vault, .vault): true
        case let (.file(_, p1), .file(_, p2)): p1 == p2
        case let (.folder(_, _, p1), .folder(_, _, p2)): p1 == p2
        default: false
        }
    }

    public func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        streamTask?.cancel()
        aiGen += 1
        let gen = aiGen
        input = ""
        isError = false
        isStreaming = false
        messages.append(ChatMessage(role: .user, text: prompt))
        isThinking = true
        let taskKey = AITaskKey.chat(context)
        tasks?.started(taskKey, label: context.historyPath(vaultRoot: vaultRoot), route: .openChat(context))
        let historySnapshot = messages
        streamTask = Task { [weak self] in
            guard let self else { return }
            await persist()
            var started = false
            do {
                for try await event in ai.chat(history: historySnapshot, context: context) {
                    if Task.isCancelled { break }
                    switch event {
                    case let .token(chunk):
                        if !started {
                            started = true
                            isThinking = false
                            isStreaming = true
                            messages.append(ChatMessage(role: .assistant, text: ""))
                        }
                        if messages.last?.role == .assistant {
                            messages[messages.count - 1].text += chunk
                            streamTick &+= 1
                        }
                    case let .action(summary):
                        isStreaming = false
                        started = false
                        messages.append(ChatMessage(role: .assistant, text: summary))
                        isThinking = true
                    case let .proposeDeletion(path, title):
                        isThinking = false
                        isStreaming = false
                        pendingDeletion = PendingDeletion(path: path, title: title)
                    }
                }
            } catch {
                guard gen == aiGen else { return }
                isThinking = false
                isStreaming = false
                isError = true
                tasks?.failed(taskKey)
                return
            }
            guard gen == aiGen else { return }
            isThinking = false
            isStreaming = false
            tasks?.finished(taskKey)
            await persist()
            await compactIfNeeded()
        }
    }

    /// Свернуть старые сообщения в одну сводку, когда чат разрастается, — чтобы промпт не
    /// раздувался и Mac не грелся, а нить разговора сохранялась. Запускается после ответа.
    private func compactIfNeeded() async {
        let keep = 12
        guard messages.count > 24 else { return }
        let old = Array(messages.dropLast(keep))
        guard old.count > 2 else { return }
        let transcript = old.map { "\($0.role == .user ? "User" : "Sage"): \($0.text)" }.joined(separator: "\n")
        var summary = ""
        do {
            for try await chunk in ai.runEditorAction(
                .summary, selection: "", document: String(transcript.prefix(8000)),
                userPrompt: "Summarize this conversation as 3-6 short bullet points: key facts, decisions and open tasks. Keep note names."
            ) { summary += chunk }
        } catch { return }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages = [ChatMessage(role: .assistant, text: "📌 " + trimmed)] + messages.suffix(keep)
        await persist()
    }

    public func confirmDeletion(deletedText: String) {
        guard let pending = pendingDeletion else { return }
        pendingDeletion = nil
        Task {
            try? await vault.deleteNote(at: URL(fileURLWithPath: pending.path))
            NotificationCenter.default.post(name: .sageVaultChanged, object: nil)
            messages.append(ChatMessage(role: .assistant, text: deletedText))
            await persist()
        }
    }

    public func cancelDeletion() {
        pendingDeletion = nil
    }

    public func stop() {
        aiGen += 1
        streamTask?.cancel()
        isThinking = false
        isStreaming = false
        tasks?.cancel(.chat(context))
    }

    public func retry() {
        isError = false
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        if messages.last?.role == .assistant { messages.removeLast() }
        input = lastUser.text
        if messages.last?.role == .user { messages.removeLast() }
        send()
    }

    /// «Очистить чат» — стирает текущую беседу безвозвратно (а не архивирует в Историю).
    public func newChat() {
        stop()
        if voice != .off { cancelVoice() }
        let old = sessionID
        messages.removeAll()
        sessionID = UUID()
        isError = false
        pendingDeletion = nil
        historyOpen = false
        isLoadingSession = false
        Task { [weak self] in
            guard let self else { return }
            await store.delete(id: old)
            sessions = ownSessions(await store.sessions())
        }
    }

    /// Перечитать список сессий из стора (история могла измениться в ДРУГОМ keep-alive VM —
    /// напр. корзина удалила беседу из стора, а этот VM держал старый список).
    public func refreshSessions() {
        Task { [weak self] in
            guard let self else { return }
            sessions = ownSessions(await store.sessions())
        }
    }

    /// Удалить конкретную сессию из Истории. Возвращает true, если удалили ТЕКУЩУЮ беседу
    /// (тогда App уводит в чат всего хранилища).
    @discardableResult
    public func deleteSession(_ session: ChatSession) -> Bool {
        let wasCurrent = session.id == sessionID
        if wasCurrent {
            stop()
            messages = []
            sessionID = UUID()
            pendingDeletion = nil
            isError = false
            historyOpen = false
            isLoadingSession = false
        }
        let deletedContext = session.context
        Task { [weak self] in
            guard let self else { return }
            await store.delete(id: session.id)
            sessions = ownSessions(await store.sessions())
            NotificationCenter.default.post(name: .sageChatSessionDeleted, object: deletedContext)
        }
        return wasCurrent
    }

    /// Снятие контекста (× на чипе) → переход в общий чат хранилища с его беседой.
    public func clearContext() {
        switchContext(to: .vault)
    }

    /// Корзина: удалить ТЕКУЩУЮ беседу безвозвратно и начать новую пустую В ТОМ ЖЕ контексте
    /// (НЕ прыгать в .vault — пользователь остаётся в папке/файле/хранилище). Чип контекста сохраняется.
    /// Постит `.sageChatSessionDeleted`, чтобы остальные keep-alive VM обновили ОБЩИЙ список истории.
    public func clearCurrentChat() {
        stop()
        if voice != .off { cancelVoice() }
        let old = sessionID
        let ctx = context
        messages.removeAll()
        sessionID = UUID()
        isError = false
        pendingDeletion = nil
        historyOpen = false
        isLoadingSession = false
        Task { [weak self] in
            guard let self else { return }
            await store.delete(id: old)
            sessions = ownSessions(await store.sessions())
            NotificationCenter.default.post(name: .sageChatSessionDeleted, object: ctx)
        }
    }

    /// Переключение контекста: загрузить существующую беседу этого контекста или начать пустую.
    public func switchContext(to newContext: ChatContext) {
        stop()
        context = newContext
        messages = []
        sessionID = UUID()
        pendingDeletion = nil
        isError = false
        historyOpen = false
        isLoadingSession = true
        Task { [weak self] in
            guard let self else { return }
            let sessions = ownSessions(await store.sessions())
            if let existing = sessions.first(where: { self.sameContext($0.context, newContext) }) {
                sessionID = existing.id
                messages = existing.messages
            }
            isLoadingSession = false
        }
    }

    public func toggleHistory() {
        historyOpen.toggle()
        if historyOpen { Task { [weak self] in guard let self else { return }; sessions = ownSessions(await store.sessions()) } }
    }

    public func openSession(_ session: ChatSession) {
        stop()
        sessionID = session.id
        context = session.context
        messages = session.messages
        historyOpen = false
        isLoadingSession = false
    }

    // MARK: - Голос

    public func toggleVoice() {
        if voice == .off { startVoice() } else { stopVoice() }
    }

    private func startVoice() {
        guard whisperAvailable, let url = whisperURL else { return }
        voicePrefix = input
        voiceAutoSend = false
        waveLevels = Array(repeating: 0.12, count: waveLevels.count)
        recordingStart = nil
        voice = .permission
        voiceTask = Task { [weak self] in
            guard let self else { return }
            let granted = await speech.requestPermission()
            guard granted else { voice = .off; return }
            for await event in speech.start(modelURL: url, language: language) {
                switch event {
                case let .phase(phase):
                    voice = phase
                    if phase == .listening, recordingStart == nil { recordingStart = Date() }
                case let .level(level):
                    waveLevels.removeFirst()
                    waveLevels.append(level)
                case let .finished(text):
                    input = Formatting.mergeVoiceText(prefix: voicePrefix, transcript: text)
                    recordingStart = nil
                    voice = .off
                    if voiceAutoSend {
                        voiceAutoSend = false
                        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() }
                    }
                case .failed:
                    recordingStart = nil
                    voice = .off
                case let .partial(text):
                    input = Formatting.mergeVoiceText(prefix: voicePrefix, transcript: text)
                }
            }
        }
    }

    /// Кнопка «✓ остановить и распознать»: завершить запись и распознать (НЕ отменять луп — иначе результат потеряется).
    public func stopVoice() {
        Task { await speech.stop() }
    }

    /// Кнопка «✓»/Enter оверлея: стоп записи → распознавание → СРАЗУ отправить в чат (инпут не показываем).
    public func confirmVoice() {
        voiceAutoSend = true
        stopVoice()
    }

    /// Отмена голоса (× оверлея / смена чата): без распознавания + ВОССТАНОВИТЬ набранный текст (стереть превью).
    public func cancelVoice() {
        voiceTask?.cancel()
        Task { await speech.stop() }
        voiceAutoSend = false
        input = voicePrefix
        recordingStart = nil
        voice = .off
    }

    private func persist() async {
        guard !messages.isEmpty else { return }
        let title = messages.first(where: { $0.role == .user })?.text ?? "Чат"
        let session = ChatSession(
            id: sessionID, title: String(title.prefix(60)),
            context: context, messages: messages, updatedAt: Date(), vaultPath: vaultRoot?.path
        )
        await store.save(session)
    }
}
