import CoreKit
import Foundation
import Observation

@MainActor
@Observable
public final class EditorViewModel {
    public var text = ""
    public var isLoading = false
    public var modifiedAt: Date?

    public var aiBarOpen = false
    public var aiPrompt = ""
    public var aiStreaming = false
    public var aiResult = ""
    public var aiError = false
    /// Намерение инлайна: применить как правку выделения (.edit) или показать как ответ (.answer).
    public var aiApplyMode: InlineApply = .answer

    public enum InlineApply: Sendable { case edit, answer }

    /// Детерминированная классификация намерения инлайна ПО ПРОМПТУ пользователя (надёжнее tag на 8B).
    /// Глаголы правки → .edit; вопрос → .answer; пусто/неясно → .edit при выделении, иначе .answer. Чистая фн.
    public static func inlineIntent(_ prompt: String, hasSelection: Bool) -> InlineApply {
        let p = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return hasSelection ? .edit : .answer }
        let editVerbs = ["перефраз", "упрост", "сократ", "расшир", "перепиш", "замен", "исправ", "правь", "поправь",
                         "переведи", "переведите", "удали", "убери", "вычеркни", "оформи", "дополни", "допиши",
                         "продолж", "сделай ", "rewrite", "rephrase", "simplify", "shorten", "expand", "replace",
                         "fix ", "translate", "delete", "remove", "continue", "make it", "turn into"]
        if editVerbs.contains(where: { p.contains($0) }) { return .edit }
        if p.hasSuffix("?") { return .answer }
        let askStarters = ["что", "почему", "зачем", "как ", "какой", "какая", "кто", "когда", "где", "сколько",
                           "о чём", "о чем", "объясни", "расскажи", "поясни", "what", "why", "how", "who",
                           "when", "where", "explain", "tell"]
        if askStarters.contains(where: { p.hasPrefix($0) }) { return .answer }
        return hasSelection ? .edit : .answer
    }

    /// «Чистое удаление» — промпт сводится РОВНО к команде удалить выделение (без иной трансформации).
    /// Тогда инлайн удаляет выделение КОДОМ, не моделью (8B почти никогда не отдаёт пустой ответ → «удали»
    /// не срабатывало). «удали лишние пробелы» — НЕ чистое удаление (остаётся цель → идёт в модель). Чистая фн.
    public static func isPureDeletion(_ raw: String) -> Bool {
        var p = " " + raw.lowercased() + " "
        let fillers = [" выделенный ", " выделенное ", " выделенную ", " выделенный текст ", " выделенный фрагмент ",
                       " выделение ", " это ", " этот ", " эту ", " текст ", " фрагмент ", " пожалуйста ", " весь ", " всё ", " все ",
                       " the ", " selected ", " selection ", " this ", " text ", " please ", " highlighted ", " whole "]
        for f in fillers { p = p.replacingOccurrences(of: f, with: " ") }
        let tokens = p.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard tokens.count == 1 else { return false }
        let deleteVerbs: Set<String> = ["удали", "удалить", "убери", "убрать", "сотри", "стереть", "вычеркни",
                                        "delete", "remove", "erase", "clear"]
        return deleteVerbs.contains(tokens[0])
    }

    public var focusedBlockText = ""
    public var focusedBlockStart: Int?
    public var focusedBlockEnd: Int?

    public var scrollTarget: String?

    public private(set) var fileURL: URL?
    /// Файл, чьё содержимое РЕАЛЬНО сейчас в `text`. Может отставать от `fileURL` во время switchTo
    /// (fileURL = целевой, выставляется до await readNote; loadedURL = загруженный, после). Сохраняем
    /// ВСЕГДА в loadedURL — иначе при быстром переключении текст старого файла уходит в новый (потеря данных).
    private var loadedURL: URL?
    /// Текст, КАК НА ДИСКЕ (последняя загрузка/запись). Если `text == diskSnapshot` — реальных правок нет,
    /// и сохранять НЕ нужно: иначе пустая перезапись бампит mtime → файл «фантомно» уезжает вверх по дате.
    private var diskSnapshot = ""
    private let vault: VaultServicing
    private let markdown: MarkdownRendering
    private let ai: AICoordinating
    /// Реестр фоновых задач ИИ (опц. — тесты/легаси передают nil).
    private let tasks: AITaskRegistry?

    private var saveTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    /// Поколение инлайн-ИИ: прерывание новым вопросом инкрементит его. Отменённый старый Task
    /// проверяет поколение перед записью терминального стейта → не клоббит новую генерацию.
    private var aiGeneration = 0
    private var renderedText = ""
    private var cachedBlocks: [MarkdownBlock] = []
    /// Идёт переключение файла — входящие правки из webview игнорируем (анти-перезапись).
    private var isSwitching = false
    /// Токен текущей загрузки: если стартовал новый switch, результат старого отбрасываем.
    private var loadToken = UUID()

    /// Инлайн-ИИ-сессии по пути файла — генерация переживает переключение файлов.
    private struct InlineState { var barOpen = false; var prompt = ""; var result = ""; var streaming = false; var error = false }
    private var inlineStash: [String: InlineState] = [:]
    private func snapshotInline() -> InlineState {
        InlineState(barOpen: aiBarOpen, prompt: aiPrompt, result: aiResult, streaming: aiStreaming, error: aiError)
    }
    private func applyInline(_ state: InlineState) {
        aiBarOpen = state.barOpen; aiPrompt = state.prompt; aiResult = state.result
        aiStreaming = state.streaming; aiError = state.error
    }

    public init(fileURL: URL?, vault: VaultServicing, markdown: MarkdownRendering, ai: AICoordinating,
                tasks: AITaskRegistry? = nil) {
        self.fileURL = fileURL
        self.loadedURL = fileURL
        self.vault = vault
        self.markdown = markdown
        self.ai = ai
        self.tasks = tasks
    }

    /// Отменить висящую инлайн-генерацию (saveTask гасит flushSave). Зовётся из EditorView.onDisappear —
    /// при пересоздании редактора (смена vault по `.id`) осиротевший Task не дописывает в старый файл.
    public func cancelInFlightAI() { aiTask?.cancel() }

    public var renderer: MarkdownRendering { markdown }

    public var blocks: [MarkdownBlock] {
        if text != renderedText {
            cachedBlocks = markdown.render(text)
            renderedText = text
        }
        return cachedBlocks
    }

    public var outline: [OutlineItem] { markdown.outline(text) }
    public var wordCount: Int { text.wordCount }

    public func load() async {
        guard let url = fileURL else { return }
        if let doc = try? await vault.readNote(at: url) {
            text = doc.text
            diskSnapshot = doc.text
            modifiedAt = doc.modifiedAt
            loadedURL = url
        }
    }

    /// Внешнее изменение открытого файла на диске (git pull / Finder). Если файл изменился на диске
    /// И у пользователя НЕТ несохранённых правок (`text == diskSnapshot`) — перезагрузить его дисковой
    /// версией (иначе автосохранение затёрло бы подтянутую заметку — потеря данных, как фантом-перезапись).
    /// При несохранённых правках НЕ трогаем (локальная версия пользователя остаётся; удалённая — в git-истории).
    /// Возвращает true, если перезагрузили (вью протолкнёт текст в webview).
    public func reconcileExternal() async -> Bool {
        guard let url = loadedURL, !isSwitching else { return false }
        guard text == diskSnapshot else { return false }
        guard let doc = try? await vault.readNote(at: url) else { return false }
        guard doc.text != diskSnapshot else { return false }
        text = doc.text
        diskSnapshot = doc.text
        modifiedAt = doc.modifiedAt
        return true
    }

    /// Переключение на другой файл БЕЗ пересоздания редактора (живой webview) — нет лага открытия.
    public func switchTo(_ url: URL?) async {
        flushSave()
        if let old = fileURL { inlineStash[old.path] = snapshotInline() }
        let token = UUID()
        loadToken = token
        isSwitching = true
        fileURL = url
        if let url {
            let doc = try? await vault.readNote(at: url)
            guard loadToken == token else { return }
            text = doc?.text ?? ""
            diskSnapshot = doc?.text ?? ""
            loadedURL = url
            modifiedAt = doc?.modifiedAt
            applyInline(inlineStash[url.path] ?? InlineState())
            if tasks?.isReadyUnread(.inline(path: url.path)) == true { tasks?.markRead(.inline(path: url.path)) }
        } else {
            text = ""
            diskSnapshot = ""
            loadedURL = nil
            applyInline(InlineState())
        }
        isSwitching = false
    }

    /// Правка, пришедшая из webview. Применяем ТОЛЬКО к актуальному файлу и не во время переключения —
    /// иначе «хвостовой» текст прошлого файла мог уйти в новый (потеря данных).
    public func onEditorText(_ newText: String) {
        guard !isSwitching, fileURL != nil, newText != text else { return }
        text = newText
        scheduleSave()
    }

    /// Немедленно и СИНХРОННО сохранить (флаш дебаунса) — при вставке картинки/закрытии/выходе.
    /// Прямая запись (не Task.detached) — иначе при Cmd-Q процесс завершается раньше, чем успеет таск.
    public func flushSave() {
        saveTask?.cancel()
        guard let url = loadedURL else { return }
        guard text != diskSnapshot else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        diskSnapshot = text
        modifiedAt = Date()
        NotificationCenter.default.post(name: .sageLocalEdit, object: nil)
    }

    public func scheduleSave() {
        saveTask?.cancel()
        guard let url = loadedURL else { return }
        let snapshot = text
        guard snapshot != diskSnapshot else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            guard let self, self.loadedURL == url else { return }
            guard snapshot != self.diskSnapshot else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try? await self.vault.writeNote(NoteDocument(url: url, text: snapshot, modifiedAt: Date()))
            self.diskSnapshot = snapshot
            self.modifiedAt = Date()
            NotificationCenter.default.post(name: .sageLocalEdit, object: nil)
        }
    }

    /// Сохранить вставленную картинку в `assets/` рядом с заметкой; вернуть относительный путь.
    public func saveAsset(_ data: Data, ext: String) async -> String? {
        guard let url = fileURL else { return nil }
        return try? await vault.saveAsset(data, ext: ext, nearNote: url)
    }

    public func toggleCheck(line: Int) {
        var lines = text.components(separatedBy: "\n")
        guard line < lines.count else { return }
        let current = lines[line]
        if current.contains("- [ ]") {
            lines[line] = current.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else if current.lowercased().contains("- [x]") {
            lines[line] = current.replacingOccurrences(of: "- [x]", with: "- [ ]", options: .caseInsensitive)
        }
        text = lines.joined(separator: "\n")
        scheduleSave()
    }

    // MARK: - Инлайн-ИИ

    public func runAI(_ action: AIAction, selection: String = "") {
        aiTask?.cancel()
        guard let startURL = fileURL else { return }
        let startPath = startURL.path
        aiGeneration += 1
        let gen = aiGeneration
        aiResult = ""
        aiError = false
        aiStreaming = true
        let mode: InlineApply = (action == .ask || action == .summary) ? .answer : .edit
        aiApplyMode = mode
        inlineStash[startPath] = snapshotInline()
        tasks?.started(.inline(path: startPath), label: startURL.lastPathComponent, route: .openInline(path: startPath))
        let prompt = aiPrompt
        let doc = text
        aiTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            var failed = false
            do {
                for try await chunk in ai.runEditorAction(action, selection: selection, document: doc, userPrompt: prompt) {
                    if Task.isCancelled || gen != aiGeneration { return }
                    acc += chunk
                    inlineStash[startPath]?.result = acc
                    if fileURL?.path == startPath { aiResult = acc }
                }
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
            guard gen == aiGeneration else { return }
            if acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, mode != .edit { failed = true }
            inlineStash[startPath]?.streaming = false
            inlineStash[startPath]?.error = failed
            if fileURL?.path == startPath { aiError = failed; aiStreaming = false }
            if failed {
                tasks?.failed(.inline(path: startPath))
            } else {
                tasks?.finished(.inline(path: startPath))
            }
        }
    }

    /// Вставить результат сразу после фокусного блока (под курсором).
    public func insertAfterFocusedBlock(_ result: String) {
        guard !result.isEmpty else { return }
        if let end = focusedBlockEnd {
            var lines = text.components(separatedBy: "\n")
            let at = min(end, lines.count)
            lines.insert(contentsOf: ["", result], at: at)
            text = lines.joined(separator: "\n")
        } else {
            if !text.hasSuffix("\n"), !text.isEmpty { text.append("\n\n") }
            text.append(result)
        }
        scheduleSave()
    }

    /// Заменить весь текст (для «Улучшить» → «Заменить»).
    public func replaceWholeText(_ result: String) {
        guard !result.isEmpty else { return }
        text = result
        scheduleSave()
    }

    /// Заменить содержимое фокусного блока (для «Заменить» по выделению в превью).
    public func replaceFocusedBlock(_ result: String) {
        guard !result.isEmpty, let start = focusedBlockStart, let end = focusedBlockEnd else {
            replaceWholeText(result); return
        }
        var lines = text.components(separatedBy: "\n")
        guard start <= lines.count else { return }
        lines.replaceSubrange(start ..< min(end, lines.count), with: result.components(separatedBy: "\n"))
        text = lines.joined(separator: "\n")
        scheduleSave()
    }

    public func dismissAI() {
        aiTask?.cancel()
        if let path = fileURL?.path { inlineStash[path] = nil; tasks?.markRead(.inline(path: path)) }
        aiBarOpen = false
        aiStreaming = false
        aiResult = ""
        aiPrompt = ""
        aiError = false
    }
}
