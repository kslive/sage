import CoreKit
import Foundation
import MarkdownService
import SageTestSupport
import XCTest
@testable import EditorFeature

@MainActor
final class EditorViewModelTests: XCTestCase {
    private var vault: MockVaultServicing!
    private var ai: MockAICoordinating!
    private var temp: TempVault!

    override func setUp() {
        super.setUp()
        vault = MockVaultServicing()
        ai = MockAICoordinating()
        temp = TempVault()
    }

    override func tearDown() {
        temp.cleanup()
        super.tearDown()
    }

    private func makeVM(fileURL: URL? = nil, tasks: AITaskRegistry? = nil) -> EditorViewModel {
        EditorViewModel(fileURL: fileURL, vault: vault, markdown: MarkdownService(), ai: ai, tasks: tasks)
    }

    private func wait(_ cond: @escaping () -> Bool, _ timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    // MARK: - Гонка переключения файлов (анти-перезапись, P0)

    /// Быстрый switchTo(B1)→switchTo(B2) пока B1 ещё грузится НЕ должен записать текст текущего
    /// файла в другой файл. Раньше flushSave писал по fileURL (уже = B1), а text был ещё от A →
    /// содержимое A уходило в файл B1. Теперь пишем по loadedURL (реально загруженный файл).
    func testRapidSwitchDoesNotCorruptOtherFile() async throws {
        let a = temp.write("A.md", "AAA")
        let b1 = temp.write("B1.md", "BBB")
        let b2 = temp.write("B2.md", "CCC")
        vault.docs[a.path] = NoteDocument(url: a, text: "AAA", modifiedAt: Date())
        vault.docs[b1.path] = NoteDocument(url: b1, text: "BBB", modifiedAt: Date())
        vault.docs[b2.path] = NoteDocument(url: b2, text: "CCC", modifiedAt: Date())

        let vm = makeVM(fileURL: a)
        await vm.load()
        XCTAssertEqual(vm.text, "AAA")

        vault.readDelayNanos = 150_000_000          // readNote повиснет на 150мс
        let s1 = Task { await vm.switchTo(b1) }      // зависнет на await readNote(b1); fileURL=b1, text="AAA"
        try await Task.sleep(nanoseconds: 30_000_000)
        let s2 = Task { await vm.switchTo(b2) }      // его flushSave — точка прошлой перезаписи
        _ = await s1.value; _ = await s2.value       // .value — дождаться РЕАЛЬНОГО завершения обоих

        // КЛЮЧЕВОЕ: B1 на диске НЕ перезаписан содержимым A.
        XCTAssertEqual(try String(contentsOf: b1, encoding: .utf8), "BBB")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "AAA")
        XCTAssertEqual(vm.text, "CCC")               // в итоге открыт B2
    }

    func testToggleCheckUncheckedToChecked() {
        let vm = makeVM()
        vm.text = "- [ ] task"
        vm.toggleCheck(line: 0)
        XCTAssertTrue(vm.text.contains("- [x]"))
    }

    // MARK: - diskSnapshot: без реальных правок не пишем (анти-фантомная-сортировка)

    func testFlushWithoutEditsDoesNotTouchMtime() async throws {
        let url = temp.write("note.md", "hello")
        vault.docs[url.path] = NoteDocument(url: url, text: "hello", modifiedAt: Date())
        let vm = makeVM(fileURL: url)
        await vm.load()                                  // diskSnapshot = "hello"
        let fm = FileManager.default
        let before = try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        try await Task.sleep(nanoseconds: 30_000_000)
        vm.flushSave()                                   // правок нет → НЕ должны писать
        let after = try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after)                    // mtime не тронут → файл не «уедет» в сортировке
    }

    func testFlushWithEditWritesAndBumpsMtime() async throws {
        let url = temp.write("note.md", "hello")
        vault.docs[url.path] = NoteDocument(url: url, text: "hello", modifiedAt: Date())
        let vm = makeVM(fileURL: url)
        await vm.load()
        vm.onEditorText("hello edited")                  // реальная правка
        vm.flushSave()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello edited")
    }

    // MARK: - reconcileExternal (git pull обновил открытый файл — анти-потеря данных, Ит.44)

    /// Внешнее изменение файла + нет локальных правок → перезагрузить дисковой версией.
    func testReconcileExternalReloadsWhenNoLocalEdits() async throws {
        let url = temp.write("note.md", "v1")
        vault.docs[url.path] = NoteDocument(url: url, text: "v1", modifiedAt: Date())
        let vm = makeVM(fileURL: url)
        await vm.load()                                  // text="v1", diskSnapshot="v1"
        vault.docs[url.path] = NoteDocument(url: url, text: "v2-from-remote", modifiedAt: Date())  // git pull
        let reloaded = await vm.reconcileExternal()
        XCTAssertTrue(reloaded)
        XCTAssertEqual(vm.text, "v2-from-remote")
    }

    /// Внешнее изменение + ЕСТЬ несохранённые локальные правки → НЕ затирать (версия пользователя остаётся).
    func testReconcileExternalKeepsLocalEdits() async throws {
        let url = temp.write("note.md", "v1")
        vault.docs[url.path] = NoteDocument(url: url, text: "v1", modifiedAt: Date())
        let vm = makeVM(fileURL: url)
        await vm.load()
        vm.onEditorText("v1-local-edit")                 // несохранённая правка (text != diskSnapshot)
        vault.docs[url.path] = NoteDocument(url: url, text: "v2-from-remote", modifiedAt: Date())
        let reloaded = await vm.reconcileExternal()
        XCTAssertFalse(reloaded)
        XCTAssertEqual(vm.text, "v1-local-edit")
    }

    /// Диск не менялся → no-op (не дёргать webview зря).
    func testReconcileExternalNoopWhenDiskUnchanged() async throws {
        let url = temp.write("note.md", "v1")
        vault.docs[url.path] = NoteDocument(url: url, text: "v1", modifiedAt: Date())
        let vm = makeVM(fileURL: url)
        await vm.load()
        let reloaded = await vm.reconcileExternal()
        XCTAssertFalse(reloaded)
        XCTAssertEqual(vm.text, "v1")
    }

    // MARK: - inlineIntent (детерминированная классификация намерения инлайна)

    func testInlineIntentEditVerbs() {
        for p in ["перефразируй", "упрости текст", "сократи", "замени Артема на Игоря", "перепиши покороче",
                  "исправь ошибки", "переведи на английский", "rewrite this", "simplify", "make it shorter"] {
            XCTAssertEqual(EditorViewModel.inlineIntent(p, hasSelection: true), .edit, "«\(p)» должно быть .edit")
        }
    }

    func testInlineIntentQuestions() {
        for p in ["что выделено?", "о чём этот текст", "почему так", "объясни это", "what is this", "how does it work"] {
            XCTAssertEqual(EditorViewModel.inlineIntent(p, hasSelection: true), .answer, "«\(p)» должно быть .answer")
        }
    }

    func testInlineIntentEmptyWithSelectionIsEdit() {
        XCTAssertEqual(EditorViewModel.inlineIntent("", hasSelection: true), .edit)
        XCTAssertEqual(EditorViewModel.inlineIntent("", hasSelection: false), .answer)
    }

    func testInlineIntentDeleteIsEdit() {
        XCTAssertEqual(EditorViewModel.inlineIntent("удали это", hasSelection: true), .edit)
    }

    func testIsPureDeletion() {
        // Чистое удаление выделения → true (удаляем кодом, не моделью).
        for p in ["удали", "Удали", "удали выделенный текст", "удали выделение", "убери это",
                  "сотри выделенный фрагмент", "delete", "delete this selected text", "remove this", "удали весь текст"] {
            XCTAssertTrue(EditorViewModel.isPureDeletion(p), "«\(p)» — чистое удаление")
        }
        // Есть иная трансформация/цель → НЕ чистое удаление (идёт в модель).
        for p in ["удали лишние пробелы", "удали последний абзац", "перефразируй", "сократи", "remove duplicates", "удали все ссылки"] {
            XCTAssertFalse(EditorViewModel.isPureDeletion(p), "«\(p)» — не чистое удаление")
        }
    }

    func testToggleCheckCheckedToUnchecked() {
        let vm = makeVM()
        vm.text = "- [x] task"
        vm.toggleCheck(line: 0)
        XCTAssertTrue(vm.text.contains("- [ ]"))
    }

    func testToggleCheckOutOfRangeNoCrash() {
        let vm = makeVM()
        vm.text = "line"
        vm.toggleCheck(line: 99)
        XCTAssertEqual(vm.text, "line")
    }

    func testReplaceWholeText() {
        let vm = makeVM()
        vm.text = "old"
        vm.replaceWholeText("new")
        XCTAssertEqual(vm.text, "new")
    }

    func testReplaceFocusedBlock() {
        let vm = makeVM()
        vm.text = "a\nold\nc"
        vm.focusedBlockStart = 1
        vm.focusedBlockEnd = 2
        vm.replaceFocusedBlock("new")
        XCTAssertEqual(vm.text, "a\nnew\nc")
    }

    func testInsertAfterFocusedBlock() {
        let vm = makeVM()
        vm.text = "a\nb"
        vm.focusedBlockEnd = 1
        vm.insertAfterFocusedBlock("X")
        XCTAssertTrue(vm.text.contains("X"))
        XCTAssertTrue(vm.text.hasPrefix("a"))
    }

    func testSaveAssetReturnsRelativePath() async {
        let vm = makeVM(fileURL: URL(fileURLWithPath: "/v/note.md"))
        let rel = await vm.saveAsset(Data([1]), ext: "png")
        XCTAssertEqual(rel, "assets/mock.png")
    }

    func testRunAIAccumulatesResult() async {
        let vm = makeVM(fileURL: URL(fileURLWithPath: "/v/note.md"))
        ai.editorTokens = ["Hel", "lo"]
        vm.runAI(.ask)
        await wait { !vm.aiStreaming && vm.aiResult == "Hello" }
        XCTAssertEqual(vm.aiResult, "Hello")
        XCTAssertFalse(vm.aiError)
    }

    func testRunAIEmptyResultSetsError() async {
        let vm = makeVM(fileURL: URL(fileURLWithPath: "/v/note.md"))
        ai.editorTokens = []
        vm.runAI(.ask)
        await wait { !vm.aiStreaming }
        XCTAssertTrue(vm.aiError)
    }

    // MARK: - onEditorText guards

    func testOnEditorTextIgnoredWhenNoFile() {
        let vm = makeVM(fileURL: nil)
        vm.onEditorText("привнесённый текст")
        XCTAssertEqual(vm.text, "")          // без файла правка из webview игнорируется
    }

    func testOnEditorTextAppliesForActiveFile() {
        let vm = makeVM(fileURL: temp.write("a.md"))
        vm.onEditorText("новый")
        XCTAssertEqual(vm.text, "новый")
    }

    // MARK: - flushSave (синхронно, прямая запись на диск)

    func testFlushSaveWritesSynchronously() {
        let url = temp.write("note.md", "old")
        let vm = makeVM(fileURL: url)
        vm.text = "свежий контент"
        vm.flushSave()
        // СРАЗУ после flushSave (без ожидания) — файл уже содержит новый текст.
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), "свежий контент")
    }

    func testFlushSaveBeatsPendingDebounce() {
        let url = temp.write("note.md", "old")
        let vm = makeVM(fileURL: url)
        vm.text = "через flush"
        vm.scheduleSave()        // запущен 600мс debounce…
        vm.flushSave()           // …но flush пишет немедленно
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), "через flush")
    }

    // MARK: - поток картинки + анти-потеря

    func testImageFlowSavesAssetAndFlushesMarkdown() async {
        let note = temp.write("note.md", "")
        let vm = makeVM(fileURL: note)
        let rel = await vm.saveAsset(Data([1, 2, 3]), ext: "png")
        XCTAssertEqual(rel, "assets/mock.png")
        // Webview вставил markdown-ссылку и флашит (минуя debounce) → текст в .md сразу.
        vm.text = "![](\(rel!))"
        vm.flushSave()
        XCTAssertEqual(try? String(contentsOf: note, encoding: .utf8), "![](assets/mock.png)")
    }

    // MARK: - switchTo (флаш старого + загрузка нового)

    func testSwitchToFlushesOldAndLoadsNew() async {
        let fileA = temp.write("a.md", "A")
        let fileB = temp.write("b.md", "B-on-disk")
        vault.docs[fileB.path] = NoteDocument(url: fileB, text: "B-content", modifiedAt: Date())
        let vm = makeVM(fileURL: fileA)
        vm.text = "A-изменён"
        await vm.switchTo(fileB)
        XCTAssertEqual(vm.fileURL, fileB)
        XCTAssertEqual(vm.text, "B-content")                       // загружен новый файл
        XCTAssertEqual(try? String(contentsOf: fileA, encoding: .utf8), "A-изменён")  // старый флашнут
    }

    func testSwitchToNilClearsText() async {
        let vm = makeVM(fileURL: temp.write("a.md", "A"))
        vm.text = "A"
        await vm.switchTo(nil)
        XCTAssertNil(vm.fileURL)
        XCTAssertEqual(vm.text, "")
    }

    // MARK: - Реестр фоновых задач (Section 05)

    func testRunAIFinishesAsReadyUnread() async {
        let registry = AITaskRegistry()
        let url = URL(fileURLWithPath: "/v/note.md")
        let vm = makeVM(fileURL: url, tasks: registry)
        ai.editorTokens = ["Hello"]
        vm.runAI(.ask)
        await wait { !vm.aiStreaming }
        // VM НЕ помечает прочитанным сам (иначе свечение гасло мгновенно) — оставляет readyUnread.
        // Решение markRead принимает App-слой (RootView/isCurrentTarget). Здесь — индикатор доживает.
        XCTAssertEqual(registry.phase(.inline(path: url.path)), .readyUnread)
    }

    func testRunAIFailureReportsErrorToRegistry() async {
        let registry = AITaskRegistry()
        let url = URL(fileURLWithPath: "/v/note.md")
        let vm = makeVM(fileURL: url, tasks: registry)
        ai.editorTokens = []                       // пусто → failed
        vm.runAI(.ask)
        await wait { !vm.aiStreaming }
        XCTAssertEqual(registry.phase(.inline(path: url.path)), .error)
        vm.dismissAI()                             // dismiss снимает запись
        XCTAssertNil(registry.phase(.inline(path: url.path)))
    }

    // Прерывание инлайн-ИИ новым вопросом во время стрима → старая генерация отменяется тихо,
    // новая идёт без ошибки (регресс: отменённый старый Task клоббил стейт → aiError=true).
    func testInterruptInlineAIDoesNotError() async {
        let slow = SlowAICoordinating(tokens: ["a", "b", "c", "d", "e"], delayMs: 20)
        let url = temp.write("note.md", "")
        let vm = EditorViewModel(fileURL: url, vault: vault, markdown: MarkdownService(), ai: slow, tasks: AITaskRegistry())
        vm.runAI(.ask)                                       // gen1
        try? await Task.sleep(nanoseconds: 30_000_000)       // дать gen1 застримить, оставив его in-flight
        vm.runAI(.ask)                                       // gen2 — прерывает gen1
        await wait { !vm.aiStreaming }
        XCTAssertFalse(vm.aiError, "прерывание не должно давать ошибку")
        XCTAssertEqual(vm.aiResult, "abcde", "результат от новой генерации, без клоббинга старой")
    }
}

/// Координатор с задержкой между токенами — чтобы детерминированно прервать генерацию mid-stream.
private final class SlowAICoordinating: AICoordinating, @unchecked Sendable {
    let tokens: [String]
    let delayMs: UInt64
    init(tokens: [String], delayMs: UInt64) { self.tokens = tokens; self.delayMs = delayMs }

    func isReady() async -> Bool { true }
    func warmUp() async {}

    func runEditorAction(_ action: AIAction, selection: String, document: String, userPrompt: String)
        -> AsyncThrowingStream<String, Error> {
        let toks = tokens, d = delayMs
        return AsyncThrowingStream { continuation in
            let task = Task {
                for t in toks {
                    try? await Task.sleep(nanoseconds: d * 1_000_000)
                    if Task.isCancelled { continuation.finish(throwing: CancellationError()); return }
                    continuation.yield(t)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func chat(history: [ChatMessage], context: ChatContext) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
