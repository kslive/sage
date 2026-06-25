import CoreKit
import Foundation
import SageTestSupport
import XCTest
@testable import ChatFeature

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var ai: MockAICoordinating!
    private var vault: MockVaultServicing!
    private var store: MockChatStoring!

    override func setUp() {
        super.setUp()
        ai = MockAICoordinating()
        vault = MockVaultServicing()
        store = MockChatStoring()
    }

    private func makeVM(_ context: ChatContext = .vault, tasks: AITaskRegistry? = nil) -> ChatViewModel {
        ChatViewModel(context: context, ai: ai, vault: vault, speech: MockTranscribing(),
                      store: store, whisperURL: nil, language: .en, tasks: tasks)
    }

    private func wait(_ cond: @escaping () -> Bool, _ timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testWhisperAvailabilityReactive() {
        let vm = makeVM()                                  // whisperURL: nil
        XCTAssertFalse(vm.whisperAvailable)                // нет модели → нет микрофона
        vm.updateWhisper(URL(fileURLWithPath: "/tmp/whisper.bin"))
        XCTAssertTrue(vm.whisperAvailable)                 // URL подгрузился → микрофон появляется (реактивно)
        vm.updateWhisper(nil)
        XCTAssertFalse(vm.whisperAvailable)
    }

    func testSendAppendsUserThenAssistant() async {
        let vm = makeVM()
        ai.chatEvents = [.token("Hel"), .token("lo")]
        vm.input = "Hi"
        vm.send()
        await wait { vm.messages.count == 2 && !vm.isBusy }
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].text, "Hi")
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.messages[1].text, "Hello")
        XCTAssertTrue(vm.streamTick > 0)
        XCTAssertGreaterThan(store.saveCount, 0)
    }

    func testSendReportsReadyUnreadToRegistry() async {
        let registry = AITaskRegistry()
        let vm = makeVM(.vault, tasks: registry)
        ai.chatEvents = [.token("Hi")]
        vm.input = "q"
        vm.send()
        await wait { !vm.isBusy }
        // Фоновый чат (его не «открывали») → ответ готов, не прочитан.
        XCTAssertEqual(registry.phase(.chat(.vault)), .readyUnread)
    }

    func testStopCancelsAndClearsRegistry() async {
        let registry = AITaskRegistry()
        let vm = makeVM(.vault, tasks: registry)
        ai.chatEvents = [.token("Hi")]
        vm.input = "q"
        vm.send()
        XCTAssertEqual(registry.phase(.chat(.vault)), .running)   // задача стартовала → спиннер
        vm.stop()                                                 // отмена/удаление чата
        XCTAssertNil(registry.phase(.chat(.vault)))              // спиннер снят немедленно
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(registry.phase(.chat(.vault)))              // терминал отменённой задачи не воскрешает
        XCTAssertFalse(vm.isBusy)
    }

    func testNewChatStopsGeneration() async {
        let registry = AITaskRegistry()
        let vm = makeVM(.vault, tasks: registry)
        ai.chatEvents = [.token("Hi")]
        vm.input = "q"
        vm.send()
        XCTAssertEqual(registry.phase(.chat(.vault)), .running)
        vm.newChat()                                             // «Очистить чат» (корзина) → stop внутри
        XCTAssertNil(registry.phase(.chat(.vault)))
        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testDeleteCurrentSessionReturnsTrue() async {
        let vm = makeVM()
        ai.chatEvents = [.token("Hi")]
        vm.input = "q"
        vm.send()
        await wait { !vm.isBusy }
        let saved = await store.sessions()
        guard let current = saved.first else { return XCTFail("сессия не сохранилась") }
        vm.historyOpen = true
        XCTAssertTrue(vm.deleteSession(current))                 // удалили ТЕКУЩУЮ → true (App уводит в vault)
        // СИНХРОННО (без await): messages пусты + история закрыта → пустой стейт появляется сразу.
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.historyOpen)
    }

    func testDeleteOtherSessionReturnsFalse() {
        let vm = makeVM()
        let other = ChatSession(id: UUID(), title: "x", context: .vault, messages: [], updatedAt: Date(), vaultPath: nil)
        XCTAssertFalse(vm.deleteSession(other))                  // не текущая → false (остаёмся на месте)
    }

    /// Пустой стейт: switchContext помечает isLoadingSession=true (грузим), после async-load → false.
    func testSwitchContextLoadingFlag() async {
        let vm = makeVM()
        vm.switchContext(to: .file(name: "a", path: "/v/a.md"))
        XCTAssertTrue(vm.isLoadingSession)          // сразу после переключения — идёт загрузка → пустой стейт не мелькает
        await wait { !vm.isLoadingSession }
        XCTAssertFalse(vm.isLoadingSession)
    }

    /// Корзина: clearCurrentChat удаляет беседу, но ОСТАЁТСЯ в текущем контексте (НЕ прыгает в .vault) —
    /// пользователь остаётся в папке/файле, чип сохраняется, показывается пустой стейт.
    func testClearCurrentChatStaysInContext() {
        let vm = makeVM()   // vault-контекст
        let folder = ChatSession(id: UUID(), title: "привет",
                                 context: .folder(name: "VPS", fileCount: 1, path: "/v/VPS"),
                                 messages: [ChatMessage(role: .user, text: "hi")], updatedAt: Date(), vaultPath: nil)
        vm.openSession(folder)                                   // context → folder
        guard case .folder = vm.context else { return XCTFail("openSession должен был сменить контекст на folder") }
        vm.clearCurrentChat()
        guard case .folder = vm.context else { return XCTFail("clearCurrentChat должен ОСТАТЬСЯ в контексте folder") }
        XCTAssertTrue(vm.messages.isEmpty)                       // беседа очищена
        XCTAssertFalse(vm.isLoadingSession)                      // пустой стейт сразу
    }

    /// Переход в другой чат (switchContext) закрывает открытую историю.
    func testSwitchContextClosesHistory() {
        let vm = makeVM()
        vm.historyOpen = true
        vm.switchContext(to: .file(name: "a", path: "/v/a.md"))
        XCTAssertFalse(vm.historyOpen, "история должна закрыться при переходе в другой чат")
    }

    /// Удаление ТЕКУЩЕЙ сессии из истории — остаётся в её контексте + пустой стейт (не уводит в .vault).
    func testDeleteSessionCurrentStaysInContext() {
        let vm = makeVM()
        let file = ChatSession(id: UUID(), title: "t", context: .file(name: "a", path: "/v/a.md"),
                               messages: [ChatMessage(role: .user, text: "hi")], updatedAt: Date(), vaultPath: nil)
        vm.openSession(file)                                     // текущая = file-сессия
        XCTAssertTrue(vm.deleteSession(file))                   // была текущей
        guard case .file = vm.context else { return XCTFail("удаление текущей сессии НЕ должно менять контекст") }
        XCTAssertTrue(vm.messages.isEmpty)
    }

    // MARK: - Пустой стейт: isLoadingSession во всех путях (без мелька/пропажи)

    func testBootstrapClearsLoadingFlag() async {
        let vm = makeVM()
        XCTAssertTrue(vm.isLoadingSession)          // до загрузки — не мелькаем пустым стейтом
        await vm.bootstrap()
        XCTAssertFalse(vm.isLoadingSession)         // загрузили (стор пуст) → пустой стейт можно показать
    }

    func testOpenSessionClearsLoadingAndSetsContext() {
        let vm = makeVM()
        let s = ChatSession(id: UUID(), title: "t", context: .file(name: "a", path: "/v/a.md"),
                            messages: [ChatMessage(role: .user, text: "hi")], updatedAt: Date(), vaultPath: nil)
        vm.openSession(s)
        XCTAssertFalse(vm.isLoadingSession)         // синхронная загрузка → флаг снят сразу
        guard case .file = vm.context else { return XCTFail("openSession ставит контекст сессии") }
        XCTAssertEqual(vm.messages.count, 1)
    }

    func testNewChatClearsLoadingFlag() {
        let vm = makeVM()
        vm.newChat()
        XCTAssertFalse(vm.isLoadingSession)         // новый пустой чат → пустой стейт сразу
        XCTAssertTrue(vm.messages.isEmpty)
    }

    // MARK: - Удаление: нотификация инвалидации keep-alive VM

    func testClearCurrentChatPostsDeletionNotification() async {
        let vm = makeVM()
        let folder = ChatSession(id: UUID(), title: "t", context: .folder(name: "VPS", fileCount: 1, path: "/v/VPS"),
                                 messages: [], updatedAt: Date(), vaultPath: nil)
        vm.openSession(folder)
        let exp = XCTNSNotificationExpectation(name: .sageChatSessionDeleted)
        exp.handler = { note in
            if case .folder = note.object as? ChatContext { return true }   // контекст удалённой беседы (НЕ .vault)
            return false
        }
        vm.clearCurrentChat()
        await fulfillment(of: [exp], timeout: 2)
    }

    func testDeleteSessionPostsDeletionNotification() async {
        let vm = makeVM()
        let s = ChatSession(id: UUID(), title: "t", context: .folder(name: "VPS", fileCount: 1, path: "/v/VPS"),
                            messages: [], updatedAt: Date(), vaultPath: nil)
        let exp = XCTNSNotificationExpectation(name: .sageChatSessionDeleted)
        vm.deleteSession(s)
        await fulfillment(of: [exp], timeout: 2)
    }

    // MARK: - Голосовой ввод (state-machine)

    private func voiceVM(_ speech: MockTranscribing) -> ChatViewModel {
        ChatViewModel(context: .vault, ai: ai, vault: vault, speech: speech, store: store,
                      whisperURL: URL(fileURLWithPath: "/tmp/whisper.bin"),
                      language: .en)
    }

    func testVoiceHappyPathFinishedCommitsText() async {
        let speech = MockTranscribing()
        speech.events = [.phase(.listening), .level(0.6), .partial("прив"), .finished("привет")]
        let vm = voiceVM(speech)
        vm.toggleVoice()
        await wait { vm.voice == .off && vm.input == "привет" }
        XCTAssertEqual(vm.input, "привет")            // распознанное в поле
        XCTAssertEqual(vm.voice, .off)
        XCTAssertNil(vm.recordingStart)               // таймер сброшен
    }

    func testVoiceListeningSetsTimerAndLevels() async {
        let speech = MockTranscribing()
        speech.finishedText = "готово"                // держим поток в .listening до stop()
        speech.events = [.phase(.listening), .level(0.9)]
        let vm = voiceVM(speech)
        vm.toggleVoice()
        await wait { vm.voice == .listening }
        XCTAssertNotNil(vm.recordingStart)            // таймер пошёл на .listening
        XCTAssertEqual(vm.waveLevels.last, 0.9)       // уровень докатился до волн
        vm.cancelVoice()                              // чистим без отправки
        await wait { vm.voice == .off }
    }

    func testVoiceConfirmAutoSendsToChat() async {
        let speech = MockTranscribing()
        speech.finishedText = "привет sage"           // что распознает Whisper при stop()
        speech.events = [.phase(.listening)]
        ai.chatEvents = [.token("привет!")]
        let vm = voiceVM(speech)
        vm.toggleVoice()
        await wait { vm.voice == .listening }
        vm.confirmVoice()                             // ✓/Enter → стоп → распознать → СРАЗУ отправить
        await wait { vm.messages.contains { $0.role == .user && $0.text == "привет sage" } }
        XCTAssertTrue(vm.input.isEmpty)               // инпут пуст — текст ушёл в чат
        XCTAssertEqual(vm.voice, .off)
        await wait { !vm.isBusy }                     // дать AI-стриму завершиться
    }

    func testVoicePartialMergesWithTypedTextNoDouble() async {
        let speech = MockTranscribing()
        speech.events = [.phase(.listening), .partial("прив"), .finished("привет")]
        let vm = voiceVM(speech)
        vm.input = "заметка"                          // уже набрано до голоса
        vm.toggleVoice()
        await wait { vm.voice == .off }
        XCTAssertEqual(vm.input, "заметка привет")    // склейка БЕЗ дубля «заметка прив привет»
    }

    func testVoiceCancelRestoresTypedText() async {
        let speech = MockTranscribing()
        speech.finishedText = "распознано"            // держим в .listening
        speech.events = [.phase(.listening), .partial("прив")]
        let vm = voiceVM(speech)
        vm.input = "заметка"
        vm.toggleVoice()
        await wait { vm.voice == .listening && vm.input == "заметка прив" }   // превью склеилось
        vm.cancelVoice()                              // × отменить
        XCTAssertEqual(vm.input, "заметка")           // вернулось набранное (превью стёрто)
        XCTAssertEqual(vm.voice, .off)
        XCTAssertNil(vm.recordingStart)
    }

    func testVoiceConfirmEmptyTranscriptDoesNotSend() async {
        let speech = MockTranscribing()
        speech.finishedText = "   "                   // Whisper вернул пусто/пробелы (тишина)
        speech.events = [.phase(.listening)]
        let vm = voiceVM(speech)
        vm.toggleVoice()
        await wait { vm.voice == .listening }
        vm.confirmVoice()
        await wait { vm.voice == .off }
        XCTAssertTrue(vm.messages.isEmpty)            // пустой текст НЕ отправляем
        XCTAssertTrue(vm.input.isEmpty)
    }

    func testVoiceUnavailableIsNoop() {
        let vm = makeVM()                             // whisperAvailable: false, whisperURL: nil
        vm.input = "текст"
        vm.toggleVoice()                              // startVoice guard падает синхронно → ничего не делаем
        XCTAssertEqual(vm.voice, .off)
        XCTAssertEqual(vm.input, "текст")             // вход не тронут
    }

    func testVoicePermissionDeniedStaysOff() async {
        let speech = MockTranscribing()
        speech.permission = false
        let vm = voiceVM(speech)
        vm.input = "заметка"
        vm.toggleVoice()
        await wait { vm.voice == .off }
        XCTAssertEqual(vm.voice, .off)
        XCTAssertEqual(vm.input, "заметка")           // вход не тронут
    }

    func testSendClearsInput() async {
        let vm = makeVM()
        ai.chatEvents = [.token("x")]
        vm.input = "Q"
        vm.send()
        XCTAssertEqual(vm.input, "")
        await wait { !vm.isBusy }
    }

    func testActionEventCreatesSeparateMessage() async {
        let vm = makeVM()
        ai.chatEvents = [.action(summary: "Создал заметку")]
        vm.input = "сделай"
        vm.send()
        await wait { vm.messages.contains { $0.text == "Создал заметку" } }
        XCTAssertTrue(vm.messages.contains { $0.role == .assistant && $0.text == "Создал заметку" })
    }

    func testProposeDeletionSetsPending() async {
        let vm = makeVM()
        ai.chatEvents = [.proposeDeletion(path: "/v/a.md", title: "a")]
        vm.input = "удали a"
        vm.send()
        await wait { vm.pendingDeletion != nil }
        XCTAssertEqual(vm.pendingDeletion?.path, "/v/a.md")
    }

    func testConfirmDeletionDeletesAndAppends() async {
        let vm = makeVM()
        ai.chatEvents = [.proposeDeletion(path: "/v/a.md", title: "a")]
        vm.input = "удали a"
        vm.send()
        await wait { vm.pendingDeletion != nil }
        vm.confirmDeletion(deletedText: "Удалено")
        let v = vault!
        await wait { vm.pendingDeletion == nil && v.deleted.contains { $0.path == "/v/a.md" } }
        XCTAssertTrue(v.deleted.contains { $0.path == "/v/a.md" })
    }

    func testBootstrapRestoresSessionByContext() async {
        let ctx = ChatContext.file(name: "n", path: "/p")
        let prior = ChatSession(id: UUID(), title: "t", context: ctx,
                                messages: [ChatMessage(id: UUID(), role: .user, text: "old", createdAt: Date())],
                                updatedAt: Date())
        store.stored = [prior]
        let vm = makeVM(ctx)
        await vm.bootstrap()
        XCTAssertEqual(vm.messages.first?.text, "old")
    }

    func testSendPromptAutoSends() async {
        let vm = makeVM()
        ai.chatEvents = [.token("answer")]
        vm.sendPrompt("auto question")
        await wait { vm.messages.count >= 2 }
        XCTAssertEqual(vm.messages.first?.text, "auto question")
    }

    func testSameContext() {
        let vm = makeVM()
        XCTAssertTrue(vm.sameContext(.vault, .vault))
        XCTAssertTrue(vm.sameContext(.file(name: "a", path: "/p"), .file(name: "b", path: "/p")))
        XCTAssertFalse(vm.sameContext(.file(name: "a", path: "/p"), .file(name: "a", path: "/q")))
        XCTAssertFalse(vm.sameContext(.vault, .file(name: "a", path: "/p")))
    }

    func testNewChatClearsMessages() async {
        let vm = makeVM()
        ai.chatEvents = [.token("x")]
        vm.input = "q"; vm.send()
        await wait { !vm.isBusy }
        vm.newChat()
        XCTAssertTrue(vm.messages.isEmpty)
    }
}
