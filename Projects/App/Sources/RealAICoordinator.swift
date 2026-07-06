import AppKit
import CoreKit
import Foundation
import InferenceService
import Localization
import ModelService
import SettingsStore

/// Реальный координатор ИИ: резолвит активную модель, строит RAG-контекст,
/// исполняет инструменты над хранилищем и стримит ответы.
struct RealAICoordinator: AICoordinating {
    let inference: Inferencing
    let models: ModelManaging
    let settings: SettingsStore
    let locale: LocaleManager
    let vault: VaultServicing

    func isReady() async -> Bool {
        await models.localURLForLLM(settings.activeLLMId) != nil
    }

    private func ensureLoaded() async throws {
        guard let spec = ModelCatalog.llm(id: settings.activeLLMId),
              let url = await models.localURLForLLM(spec.id) else {
            throw InferenceError.notLoaded
        }
        try await inference.load(modelURL: url, template: spec.template, contextSize: spec.contextSize)
    }

    var languageName: String { locale.language.englishName }

    /// Приветствие / благодарность / болтовня — отвечаем без агентного цикла и инструментов.
    func isSmallTalk(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        let phrases = ["как дела", "как ты", "что нового", "how are you", "whats up",
                       "добрый день", "доброе утро", "добрый вечер", "good morning", "good evening"]
        let joined = words.joined(separator: " ")
        if phrases.contains(where: { joined.contains($0) }) { return true }
        let greetings: Set<String> = ["привет", "приветик", "здравствуй", "здравствуйте", "хай", "ку", "дарова",
                                      "здарова", "hello", "hi", "hey", "yo", "hola", "спасибо", "спс", "благодарю",
                                      "thanks", "thx", "thank", "пока", "bye", "ок", "окей", "ok", "okay", "угу", "ага"]
        return words.count <= 2 && words.allSatisfy { greetings.contains($0) }
    }

    private func t(_ ru: String, _ en: String, _ zh: String) -> String {
        switch locale.language {
        case .ru: ru
        case .en: en
        case .zh: zh
        }
    }

    // MARK: - Редактор (без инструментов)

    func runEditorAction(_ action: AIAction, selection: String, document: String, userPrompt: String)
        -> AsyncThrowingStream<String, Error> {
        let context = selection.isEmpty ? document : selection
        let system: String
        let instruction: String
        switch action {
        case .transform:
            if selection.isEmpty {
                system = """
                You are a markdown editing engine. The user gives an instruction; produce the text that fulfils it, ready to be inserted at the cursor. Output ONLY the resulting markdown text — no preamble, no explanations, no surrounding quotes or code fences. Keep the language of the surrounding document unless the instruction says otherwise.

                DOCUMENT:
                \(document.prefix(6000))
                """
                instruction = userPrompt
            } else {
                system = """
                You are a markdown editing engine. The user selected a fragment and gives an instruction. Apply the instruction to the SELECTED TEXT and output ONLY the resulting replacement text — no preamble, no explanations, no surrounding quotes or code fences. Return the WHOLE edited fragment, not a comment about it. ALWAYS produce a CHANGED version that reflects the instruction — never echo the input unchanged. Preserve the original language unless the instruction says otherwise.

                SELECTED TEXT:
                \(selection.prefix(6000))
                """
                instruction = userPrompt.isEmpty ? "Rewrite the selected text." : userPrompt
            }
        case .improve:
            instruction = "Apply this: improve clarity and style. Output ONLY the improved text, no explanations."
            system = "You are a markdown editing engine. Output ONLY the resulting text.\n\nTEXT:\n\(context.prefix(6000))"
        case .summary:
            instruction = "Summarize the text concisely."
            system = "You are Sage, a writing assistant. Respond in \(languageName).\n\nTEXT:\n\(context.prefix(6000))"
        case .continueText:
            instruction = "Continue writing naturally. Output ONLY the continuation."
            system = "You are a markdown editing engine. Output ONLY the new text to append.\n\nTEXT:\n\(context.prefix(6000))"
        case .ask:
            instruction = userPrompt.isEmpty ? "Answer questions about the text below." : userPrompt
            system = "You are Sage, a writing assistant inside a Markdown editor. Answer the user's question about the text below — do NOT rewrite or output the text itself. Respond in \(languageName).\n\nTEXT:\n\(context.prefix(6000))"
        }
        let request = InferenceRequest(system: system, user: instruction, temperature: settings.temperature)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ensureLoaded()
                    for try await token in inference.stream(request) { continuation.yield(token) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Чат (агент с инструментами)

    func chat(history: [ChatMessage], context: ChatContext) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ensureLoaded()
                    let root = settings.resolveVaultURL()
                    var tree = await rootTree(root)
                    let lastUser = history.last(where: { $0.role == .user })?.text ?? ""

                    if isSmallTalk(lastUser) {
                        let sys = "You are Sage, a friendly local assistant for the user's Markdown notes. Reply briefly and warmly in \(languageName). Plain text only — never use tools or JSON."
                        var any = false
                        for try await token in inference.stream(InferenceRequest(system: sys, user: lastUser, temperature: settings.temperature)) {
                            if Task.isCancelled { break }
                            any = true
                            continuation.yield(.token(token))
                        }
                        if !any {
                            continuation.yield(.token(t(
                                "Привет! Чем помочь с заметками?",
                                "Hi! How can I help with your notes?",
                                "你好！需要我帮你处理笔记吗？")))
                        }
                        continuation.finish()
                        return
                    }

                    let currentURL: URL? = switch context {
                    case let .file(_, path): URL(fileURLWithPath: path)
                    case let .folder(_, _, path): URL(fileURLWithPath: path)
                    default: settings.currentNotePath.map { URL(fileURLWithPath: $0) }
                    }
                    let scope: URL? = switch context {
                    case let .folder(_, _, path): URL(fileURLWithPath: path)
                    case let .file(_, path): URL(fileURLWithPath: path).deletingLastPathComponent()
                    default: root
                    }
                    let focus = await focusContext(context, root: root, query: lastUser, currentURL: currentURL)
                    var priorMsgs = Array(history.dropLast().suffix(6))
                    if let first = history.first, first.text.hasPrefix("📌"),
                       !priorMsgs.contains(where: { $0.id == first.id }) {
                        priorMsgs.insert(first, at: 0)
                    }
                    let prior = priorMsgs
                        .map { "\($0.role == .user ? "User" : "Sage"): \(String($0.text.prefix(600)))" }
                        .joined(separator: "\n")

                    var done: [String] = []
                    var seen = Set<String>()
                    var repeats = 0
                    var finalEmitted = false
                    var didAction = false
                    var steps = 0
                    while steps < 12 {
                        steps += 1
                        let transcript = done.isEmpty ? "" :
                            "STEPS ALREADY DONE (do NOT repeat these — continue with the next needed action, or reply when finished):\n"
                            + done.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                        let stepFocus = steps == 1 ? focus : ""
                        let system = agentSystem(root: root, context: context, tree: tree, focus: stepFocus, prior: prior, scratch: transcript)
                        let request = InferenceRequest(system: system, user: lastUser, temperature: min(settings.temperature, 0.3))
                        var buffer = ""
                        for try await token in inference.stream(request) { buffer += token }

                        if let tool = AITool.parse(from: buffer) {
                            let sig = toolSignature(tool)
                            if seen.contains(sig) {
                                repeats += 1
                                done.append("(\(tool.name) already done — skipped repeat)")
                                if repeats >= 4 { break }
                                continue
                            }
                            seen.insert(sig)
                            let result = try await perform(tool, root: root, tree: tree, current: currentURL, scope: scope, continuation: continuation)
                            didAction = true
                            done.append("\(tool.name): \(result.observation)")
                            tree = await rootTree(root)
                            if result.stop { finalEmitted = true; break }
                            continue
                        }
                        let answer = AITool.stripToolJSON(buffer)
                        if !answer.isEmpty { continuation.yield(.token(answer)); finalEmitted = true }
                        break
                    }

                    if !finalEmitted {
                        if didAction {
                        } else {
                            let wrapSystem = "You are Sage. Answer the user briefly in \(languageName). Plain text only, no JSON."
                            var any = false
                            for try await token in inference.stream(InferenceRequest(system: wrapSystem, user: lastUser, temperature: settings.temperature)) {
                                any = true; continuation.yield(.token(token))
                            }
                            if !any {
                                continuation.yield(.token(t(
                                    "Не удалось получить ответ от модели. Попробуйте переформулировать или сменить модель в настройках.",
                                    "Couldn't get a response from the model. Try rephrasing or switching the model in settings.",
                                    "未能从模型获取回复。请尝试重新表述或在设置中切换模型。")))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct ToolResult { let observation: String; var stop = false }

    /// Где сейчас «находится» пользователь — с полным относительным путём, родителем и глубиной,
    /// чтобы ИИ точно понимал, откуда к ней обращаются.
    func currentFolderLine(_ context: ChatContext, root: URL?) -> String {
        func rel(_ p: String) -> String {
            guard let root else { return URL(fileURLWithPath: p).lastPathComponent }
            return URL(fileURLWithPath: p).relativePath(from: root)
        }
        switch context {
        case .vault:
            return "CURRENT LOCATION: the WHOLE vault (root). The user asks about the entire vault."
        case let .folder(name, count, path):
            let r = rel(path)
            let parent = (r as NSString).deletingLastPathComponent
            let parentStr = parent.isEmpty ? "vault root" : parent
            return "CURRENT LOCATION: folder \"\(name)\" (path: \(r)/, parent: \(parentStr), notes inside: \(count)). The user asks about THIS folder and its notes — not other folders."
        case let .file(_, path):
            let r = rel(path)
            let folder = (r as NSString).deletingLastPathComponent
            let folderStr = folder.isEmpty ? "vault root" : folder
            return "CURRENT LOCATION: file \(r) (inside folder \(folderStr)). The user asks about THIS note."
        case let .selection(fileName):
            return "CURRENT LOCATION: a selected text fragment inside \(fileName)."
        }
    }

    /// Минимальный системный промпт: контекст + список инструментов, без ограничений (полный доступ).
    private func agentSystem(root: URL?, context: ChatContext, tree: FileNode?, focus: String, prior: String, scratch: String) -> String {
        let rootName = root?.lastPathComponent ?? "(no vault)"
        let treeStr = tree.map(treeText) ?? "(empty)"
        var s = "You are Sage, a local assistant that fully manages the user's Markdown notes. You work ONLY with .md files in Markdown format. Reply in \(languageName). When you mention, recommend, list or find a note, ALWAYS cite it as a clickable markdown link [Title](path), using the exact link/path given in the CURRENT FOLDER section or tool results — never a bare filename.\n\n"
        s += Formatting.dateContext() + "\n\n"
        s += "To list, summarize or answer questions about the current folder and its notes (\"these notes\", \"this folder\", \"each note\", \"what's here\"), use the CURRENT FOLDER / CURRENT NOTE / RELATED NOTES sections below DIRECTLY and answer in plain text — do NOT call list_folder or read_note for notes already shown there. Use tools only for changes (create/edit/append/move/rename/delete) or to read a note that is NOT already provided below.\n\n"
        if case .vault = context {
            s += "You are in WHOLE-VAULT chat. To answer about the user's notes, FIRST use search_notes (and read_note for hits) to find relevant notes by keyword/date — do not guess from the tree alone.\n\n"
        }
        s += "VAULT ROOT: \(rootName)\n\(currentFolderLine(context, root: root))\nVAULT TREE (├──/└── show nesting; each line ends with its exact path; a folder's children are the lines indented under it):\n\(String(treeStr.prefix(2500)))"
        if !focus.isEmpty { s += "\n\n\(String(focus.prefix(10000)))" }
        if !prior.isEmpty { s += "\n\nCONVERSATION:\n\(String(prior.prefix(1000)))" }
        if !scratch.isEmpty { s += "\n\nTOOL RESULTS SO FAR:\(scratch)" }
        s += "\n\n\(AITool.agentSpec)"
        return s
    }

    // MARK: - Исполнение инструментов

    /// Исполняет один инструмент: мутации шлют UI-событие, инфо-инструменты возвращают наблюдение для цикла.
    private func perform(_ tool: AITool, root: URL?, tree: FileNode?, current: URL?, scope: URL?,
                         continuation: AsyncThrowingStream<AssistantEvent, Error>.Continuation) async throws -> ToolResult {
        switch tool {
        case let .createNote(folder, title, content):
            guard let dir = await resolveOrCreateFolder(folder, tree: tree, root: root, base: scope) else {
                return ToolResult(observation: "No vault selected.")
            }
            do {
                let url = try await vault.createNote(named: title, content: content ?? "", in: dir)
                postChanged(url: url, created: true)
                let place = folder.map { " → «\($0)»" } ?? ""
                continuation.yield(.action(summary: t("📄 Создал заметку «\(title)»\(place)", "📄 Created note “\(title)”\(place)", "📄 已创建笔记《\(title)》\(place)")))
                return ToolResult(observation: "Created note \"\(title)\" in folder \(dir.lastPathComponent)\(content != nil ? " with content" : " (empty)").")
            } catch { writeFailed(continuation); return ToolResult(observation: "Failed to create note.") }

        case let .createFolder(parent, name):
            guard let parentDir = await resolveOrCreateFolder(parent, tree: tree, root: root, base: scope) else {
                return ToolResult(observation: "No vault selected.")
            }
            do {
                let url = try await vault.createFolder(named: name, in: parentDir)
                postChanged(url: url, created: false)
                continuation.yield(.action(summary: t("📁 Создал папку «\(name)»", "📁 Created folder “\(name)”", "📁 已创建文件夹《\(name)》")))
                return ToolResult(observation: "Created folder \"\(name)\".")
            } catch { writeFailed(continuation); return ToolResult(observation: "Failed to create folder.") }

        case let .appendNote(target, content):
            guard let url = resolveNote(target, tree: tree, current: current) else { notFound(target, continuation); return ToolResult(observation: "Note \"\(target)\" not found.") }
            do {
                var doc = try await vault.readNote(at: url); doc.text += "\n\n" + content
                try await vault.writeNote(doc); postChanged(url: url, created: false)
                let name = url.deletingPathExtension().lastPathComponent
                continuation.yield(.action(summary: t("✍️ Дописал в «\(name)»", "✍️ Appended to “\(name)”", "✍️ 已追加到《\(name)》")))
                return ToolResult(observation: "Appended content to \"\(name)\".")
            } catch { writeFailed(continuation); return ToolResult(observation: "Failed to write to note.") }

        case let .editNote(target, content):
            guard let url = resolveNote(target, tree: tree, current: current) else { notFound(target, continuation); return ToolResult(observation: "Note \"\(target)\" not found.") }
            do {
                var doc = try await vault.readNote(at: url); doc.text = content
                try await vault.writeNote(doc); postChanged(url: url, created: false)
                let name = url.deletingPathExtension().lastPathComponent
                continuation.yield(.action(summary: t("✏️ Обновил «\(name)»", "✏️ Updated “\(name)”", "✏️ 已更新《\(name)》")))
                return ToolResult(observation: "Replaced content of \"\(name)\".")
            } catch { writeFailed(continuation); return ToolResult(observation: "Failed to write to note.") }

        case let .renameNote(target, newName):
            guard let url = resolveNote(target, tree: tree, current: current) else { notFound(target, continuation); return ToolResult(observation: "Note \"\(target)\" not found.") }
            do {
                let newURL = try await vault.rename(at: url, to: newName); postChanged(url: newURL, created: false)
                continuation.yield(.action(summary: t("✏️ Переименовал в «\(newName)»", "✏️ Renamed to “\(newName)”", "✏️ 已重命名为《\(newName)》")))
                return ToolResult(observation: "Renamed to \"\(newName)\".")
            } catch { writeFailed(continuation); return ToolResult(observation: "Failed to rename.") }

        case let .moveNote(target, toFolder):
            guard let url = resolveNote(target, tree: tree, current: current),
                  let dir = await resolveOrCreateFolder(toFolder, tree: tree, root: root, base: scope) else {
                continuation.yield(.action(summary: t("Не нашёл заметку или папку.", "Couldn't find the note or folder.", "未找到笔记或文件夹。")))
                return ToolResult(observation: "Note or folder not found.")
            }
            do {
                try await vault.moveNote(at: url, to: dir); postChanged(url: url, created: false)
                continuation.yield(.action(summary: t("📁 Переместил «\(target)» → «\(toFolder)»", "📁 Moved “\(target)” → “\(toFolder)”", "📁 已移动《\(target)》→《\(toFolder)》")))
                return ToolResult(observation: "Moved \"\(target)\" to \"\(toFolder)\".")
            } catch { writeFailed(continuation); return ToolResult(observation: "Failed to move.") }

        case let .deleteNote(target):
            guard let url = resolveNote(target, tree: tree, current: current) else { notFound(target, continuation); return ToolResult(observation: "Note \"\(target)\" not found.") }
            continuation.yield(.proposeDeletion(path: url.path, title: url.deletingPathExtension().lastPathComponent))
            return ToolResult(observation: "Asked the user to confirm deleting \"\(target)\".", stop: true)

        case let .deleteFolder(name):
            guard let dir = findNode(in: tree, isDir: true, name: name)?.url else {
                continuation.yield(.action(summary: t("Не нашёл папку «\(name)».", "Couldn't find folder “\(name)”.", "未找到文件夹《\(name)》。")))
                return ToolResult(observation: "Folder \"\(name)\" not found.")
            }
            continuation.yield(.proposeDeletion(path: dir.path, title: name))
            return ToolResult(observation: "Asked the user to confirm deleting folder \"\(name)\".", stop: true)

        case let .deleteNotes(matching):
            let urls = matchingNotes(matching, tree: tree)
            guard !urls.isEmpty else { return ToolResult(observation: "No notes match \"\(matching)\".") }
            var names: [String] = []
            for url in urls {
                if (try? await vault.deleteNote(at: url)) != nil {
                    names.append(url.deletingPathExtension().lastPathComponent)
                    postChanged(url: url, created: false)
                }
            }
            let list = names.map { "«\($0)»" }.joined(separator: ", ")
            continuation.yield(.action(summary: t("🗑 Удалил в Корзину (\(names.count)): \(list)", "🗑 Moved to Trash (\(names.count)): \(list)", "🗑 已移至废纸篓(\(names.count))：\(list)")))
            return ToolResult(observation: "Deleted \(names.count) notes to Trash: \(list).")

        case let .searchNotes(query):
            let observation = await searchObservation(query, root: root)
            return ToolResult(observation: "Search results for \"\(query)\":\n\(observation)")

        case let .listFolder(folder):
            return ToolResult(observation: "Folder listing:\n\(listObservation(folder, tree: tree, root: root))")

        case let .readNote(target):
            guard let url = resolveNote(target, tree: tree, current: current) else { notFound(target, continuation); return ToolResult(observation: "Note \"\(target)\" not found.") }
            let doc = try await vault.readNote(at: url)
            let rel = root.map { url.relativePath(from: $0) } ?? url.lastPathComponent
            let title = url.deletingPathExtension().lastPathComponent
            return ToolResult(observation: "Content of [\(title)](\(Self.mdPath(rel))):\n\(String(doc.text.prefix(4000)))")
        }
    }

    /// Заметки для массового удаления (делегирует в чистый AILinkResolver).
    func matchingNotes(_ q: String, tree: FileNode?) -> [URL] {
        AILinkResolver.matchingNotes(q, tree: tree)
    }

    /// Подпись инструмента для дедупа повторов в агентном цикле.
    func toolSignature(_ tool: AITool) -> String {
        switch tool {
        case let .createNote(folder, title, _): return "create_note|\(folder ?? "")|\(title.lowercased())"
        case let .createFolder(parent, name): return "create_folder|\(parent ?? "")|\(name.lowercased())"
        case let .appendNote(target, _): return "append_note|\(target.lowercased())"
        case let .editNote(target, _): return "edit_note|\(target.lowercased())"
        case let .renameNote(target, newName): return "rename_note|\(target.lowercased())|\(newName.lowercased())"
        case let .moveNote(target, toFolder): return "move_note|\(target.lowercased())|\(toFolder.lowercased())"
        case let .deleteNote(target): return "delete_note|\(target.lowercased())"
        case let .deleteFolder(name): return "delete_folder|\(name.lowercased())"
        case let .deleteNotes(matching): return "delete_notes|\(matching.lowercased())"
        case let .searchNotes(query): return "search_notes|\(query.lowercased())"
        case let .listFolder(folder): return "list_folder|\(folder?.lowercased() ?? "")"
        case let .readNote(target): return "read_note|\(target.lowercased())"
        }
    }

    private func notFound(_ target: String, _ continuation: AsyncThrowingStream<AssistantEvent, Error>.Continuation) {
        continuation.yield(.action(summary: t("Не нашёл заметку «\(target)».", "Couldn't find note “\(target)”.", "未找到笔记《\(target)》。")))
    }

    private func writeFailed(_ continuation: AsyncThrowingStream<AssistantEvent, Error>.Continuation) {
        continuation.yield(.action(summary: t("⚠️ Не удалось записать в файл.", "⚠️ Couldn't write to the file.", "⚠️ 无法写入文件。")))
    }

    private func postChanged(url: URL, created: Bool) {
        let info: [String: Any] = ["url": url, "created": created]
        Task { @MainActor in
            NotificationCenter.default.post(name: .sageVaultChanged, object: nil, userInfo: info)
        }
    }

    // MARK: - Контекст / дерево / резолв

    private func rootTree(_ root: URL?) async -> FileNode? {
        guard let root else { return nil }
        return try? await vault.buildTree(at: root)
    }

    /// ASCII-дерево с явной вложенностью (├──/└──) и относительным путём у папок —
    /// модель так читает иерархию надёжно (плоские отступы путали даже Qwen).
    func treeText(_ node: FileNode) -> String {
        var lines: [String] = []
        func walk(_ n: FileNode, indent: String, pathPrefix: String) {
            let kids = n.children
            for (i, child) in kids.enumerated() {
                if lines.count > 300 { return }
                let last = i == kids.count - 1
                let connector = last ? "└── " : "├── "
                let rel = pathPrefix.isEmpty ? child.name : pathPrefix + "/" + child.name
                if child.isDirectory {
                    lines.append(indent + connector + "📁 \(child.name)/   (path: \(rel)/)")
                    walk(child, indent: indent + (last ? "    " : "│   "), pathPrefix: rel)
                } else {
                    lines.append(indent + connector + "📄 \(child.name)   (path: \(rel))")
                }
            }
        }
        walk(node, indent: "", pathPrefix: "")
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    /// Путь для markdown-ссылки (делегирует в AILinkResolver): пробелы → `<...>` (CommonMark).
    static func mdPath(_ rel: String) -> String { AILinkResolver.mdPath(rel) }

    /// Первая непустая строка заметки (делегирует в AILinkResolver).
    static func firstLine(_ text: String) -> String { AILinkResolver.firstLine(text) }

    /// Фокус-контекст для ИИ: открытая заметка + выделение + связанные заметки/папка (под бюджет токенов).
    private func focusContext(_ context: ChatContext, root: URL?, query: String, currentURL: URL?) async -> String {
        var parts: [String] = []
        let injectOpenNote: Bool
        switch context {
        case .file, .selection: injectOpenNote = true
        case .vault, .folder: injectOpenNote = false
        }
        if injectOpenNote, let currentURL, let doc = try? await vault.readNote(at: currentURL) {
            let name = currentURL.deletingPathExtension().lastPathComponent
            parts.append("CURRENT NOTE \"\(name)\":\n" + String(doc.text.prefix(8000)))
        }
        if let sel = settings.currentSelection?.trimmingCharacters(in: .whitespacesAndNewlines), !sel.isEmpty {
            parts.append("CURRENT SELECTION:\n" + String(sel.prefix(1500)))
        }
        switch context {
        case .vault:
            let r = await retrieval(query: query, root: root)
            if !r.isEmpty { parts.append(r) }
        case let .file(_, path):
            let url = URL(fileURLWithPath: path)
            if url != currentURL, let doc = try? await vault.readNote(at: url) {
                parts.append("File \(url.lastPathComponent):\n" + String(doc.text.prefix(8000)))
            }
        case let .folder(name, _, path):
            let folderURL = URL(fileURLWithPath: path)
            let files = Array(await vault.allMarkdownFiles(under: folderURL).prefix(40))
            var combined = "FOLDER \"\(name)\" — notes here (cite EXACTLY with these markdown links):\n"
            for file in files {
                let rel = root.map { file.relativePath(from: $0) } ?? file.lastPathComponent
                let title = file.deletingPathExtension().lastPathComponent
                let snippet = (try? await vault.readNote(at: file)).map { Self.firstLine($0.text) } ?? ""
                combined += snippet.isEmpty ? "- [\(title)](\(Self.mdPath(rel)))\n" : "- [\(title)](\(Self.mdPath(rel))) — \(snippet)\n"
            }
            if let tree = try? await vault.buildTree(at: folderURL) {
                let subs = tree.children.filter { $0.isDirectory }.map(\.name)
                if !subs.isEmpty { combined += "Subfolders: \(subs.joined(separator: ", "))\n" }
            }
            combined += "To read or summarize a note in full, use read_note with its path."
            parts.append(combined)
        case .selection:
            break
        }
        return parts.joined(separator: "\n\n")
    }

    /// Лёгкий retrieval по всем заметкам: топ-совпадения по словам запроса + сниппеты.
    private func retrieval(query: String, root: URL?) async -> String {
        guard let root else { return "" }
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
        guard !words.isEmpty else { return "" }
        let files = await vault.allMarkdownFiles(under: root)
        var scored: [(URL, Int, String)] = []
        for file in files {
            guard let doc = try? await vault.readNote(at: file) else { continue }
            let hay = (file.lastPathComponent + " " + doc.text).lowercased()
            let score = words.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
            if score > 0 { scored.append((file, score, doc.text)) }
        }
        scored.sort { $0.1 > $1.1 }
        let top = scored.prefix(3)
        guard !top.isEmpty else { return "" }
        var s = "RELATED NOTES (cite each EXACTLY as the given markdown link):\n"
        for (url, _, text) in top {
            let rel = url.relativePath(from: root)
            let title = url.deletingPathExtension().lastPathComponent
            s += "\n## [\(title)](\(Self.mdPath(rel)))\n" + String(text.prefix(800)) + "\n"
        }
        return s
    }

    /// Резолвит папку по имени; если её нет — создаёт. Если имя не задано — возвращает `base`
    /// (зона видимости: текущая папка), иначе корень. Scope-safety: компоненты `..`/`.`/абсолютные
    /// отклоняются, результат гарантированно ВНУТРИ vault root (ИИ не может выйти за пределы).
    func resolveOrCreateFolder(_ name: String?, tree: FileNode?, root: URL?, base: URL? = nil) async -> URL? {
        guard let root else { return nil }
        let start = base ?? root
        guard let name, !name.isEmpty else { return start }
        if !name.contains("/"), let match = findNode(in: tree, isDir: true, name: name) { return match.url }
        var dir = root
        for raw in name.split(separator: "/") {
            let comp = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'`"))
            if comp.isEmpty || comp == "." || comp == ".." { continue }
            let childDirs = await vault.childDirectories(at: dir)
            if let existing = childDirs.first(where: { $0.lastPathComponent.localizedCaseInsensitiveCompare(comp) == .orderedSame }) {
                dir = existing
            } else if let created = try? await vault.createFolder(named: comp, in: dir) {
                dir = created
            } else {
                return dir
            }
        }
        let rootPath = root.standardizedFileURL.path
        guard dir.standardizedFileURL.path == rootPath || dir.standardizedFileURL.path.hasPrefix(rootPath + "/") else { return root }
        return dir
    }

    /// Резолв заметки (делегирует в чистый AILinkResolver): алиасы → current, полный путь, leaf, fuzzy.
    func resolveNote(_ target: String, tree: FileNode?, current: URL?) -> URL? {
        AILinkResolver(tree: tree, current: current).resolveNote(target)
    }

    /// Поиск узла дерева по имени/сегментам (делегирует в AILinkResolver).
    func findNode(in node: FileNode?, isDir: Bool, name: String) -> FileNode? {
        AILinkResolver.findNode(in: node, isDir: isDir, name: name)
    }

    private func listObservation(_ folder: String?, tree: FileNode?, root: URL?) -> String {
        let node: FileNode?
        if let folder, !folder.isEmpty { node = findNode(in: tree, isDir: true, name: folder) ?? tree } else { node = tree }
        guard let node else { return "(empty)" }
        let items = node.children.map { child -> String in
            if child.isDirectory { return "📁 \(child.name)/" }
            let rel = root.map { child.url.relativePath(from: $0) } ?? child.name
            return "- [\(child.name.withoutMDExtension)](\(Self.mdPath(rel)))"
        }
        return items.isEmpty ? "(empty)" : items.joined(separator: "\n")
    }

    private func searchObservation(_ query: String, root: URL?) async -> String {
        guard let root else { return "(no vault)" }
        let files = await vault.allMarkdownFiles(under: root)
        var hits: [String] = []
        let q = query.lowercased()
        for file in files {
            guard let doc = try? await vault.readNote(at: file) else { continue }
            if file.lastPathComponent.lowercased().contains(q) || doc.text.lowercased().contains(q) {
                let title = file.deletingPathExtension().lastPathComponent
                hits.append("- [\(title)](\(Self.mdPath(file.relativePath(from: root))))")
            }
            if hits.count >= 12 { break }
        }
        return hits.isEmpty ? "(no matches)" : hits.joined(separator: "\n")
    }

    /// Путь файла относительно корня хранилища (для цитирования заметок ссылками).
}
