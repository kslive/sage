import Foundation

/// Инструмент, который ИИ может вызвать над хранилищем заметок.
public enum AITool: Sendable, Equatable {
    case createNote(folder: String?, title: String, content: String?)
    case createFolder(parent: String?, name: String)
    case deleteNote(target: String)
    case searchNotes(query: String)
    case listFolder(folder: String?)
    case readNote(target: String)
    case appendNote(target: String, content: String)
    case editNote(target: String, content: String)
    case renameNote(target: String, newName: String)
    case moveNote(target: String, toFolder: String)
    case deleteFolder(name: String)
    case deleteNotes(matching: String)

    /// Имя инструмента (для логов/наблюдений в агентном цикле).
    public var name: String {
        switch self {
        case .createNote: "create_note"
        case .createFolder: "create_folder"
        case .deleteNote: "delete_note"
        case .deleteNotes: "delete_notes"
        case .deleteFolder: "delete_folder"
        case .searchNotes: "search_notes"
        case .listFolder: "list_folder"
        case .readNote: "read_note"
        case .appendNote: "append_note"
        case .editNote: "edit_note"
        case .renameNote: "rename_note"
        case .moveNote: "move_note"
        }
    }

    /// Краткая спека для агентного цикла: полный доступ, цепочки инструментов, без ограничений.
    public static let agentSpec = """
    You have FULL access to the user's notes and can do anything they ask. To perform an action, output ONE JSON object and NOTHING ELSE (no prose around it): {"tool":"name","args":{...}}. Use plain argument keys WITHOUT any "?" character. After each tool runs you receive its result; you may call more tools to chain steps, and when done reply to the user in plain text.

    WHEN TO USE A TOOL: ONLY when the user explicitly asks to find, list, read, create, edit, append, move, rename or delete notes or folders. For greetings ("привет", "hi"), thanks, small talk, or general questions — reply DIRECTLY in plain text and DO NOT output any JSON or call any tool.

    EDIT vs DELETE — IMPORTANT: to change, clear, shorten or REWRITE the TEXT inside a note (e.g. "удали весь текст и перепиши", "rewrite this note", "clear the note"), use edit_note with the new full content (pass an empty content to clear the body) — do NOT use delete_note. delete_note and delete_folder PERMANENTLY remove the whole note/folder and must be used ONLY when the user asks to delete the note/folder itself.

    REPLACE / EDIT TEXT — YOU MUST DO IT YOURSELF: for requests like "замени X на Y", "replace X with Y", "rename Артем to Игорь in the file", "поправь/исправь текст" — do NOT tell the user how to do it and NEVER refuse. Perform it: FIRST call read_note to get the note's current content, THEN call edit_note with the FULL new content where the replacement/edit is applied. If the user just says "замени сам" / "do it", proceed with read_note then edit_note. Always act; never reply with manual instructions when you have a tool for it.

    MULTI-STEP — COMPLETE THE WHOLE REQUEST: do ONE tool per turn, but KEEP CALLING tools turn after turn until EVERYTHING the user asked is done. Look at "STEPS ALREADY DONE" and continue with the NEXT needed action; NEVER repeat an action already listed there; NEVER stop with a text reply while actions remain. For N files, call create_note N times (one per turn). To create a note with text in one go, use create_note with folder, title AND content. Only when ALL requested actions are complete, reply to the user in plain text (no JSON).
    EXAMPLE — "создай папку Проект и в ней файлы a, b, c" → turn1 {"tool":"create_folder","args":{"name":"Проект"}}; turn2 {"tool":"create_note","args":{"folder":"Проект","title":"a"}}; turn3 {"tool":"create_note","args":{"folder":"Проект","title":"b"}}; turn4 {"tool":"create_note","args":{"folder":"Проект","title":"c"}}; turn5 reply "Готово". Do NOT create the folder twice.

    CAPABILITIES (you can do all of this, no confirmations needed except deletion): create/rename/move notes and folders, create files inside folders (incl. nested), write or append Markdown content, edit/rewrite a note's body ("open file X and write a poem there" → edit_note target X with the poem). delete_note/delete_folder ask the user to confirm.

    SCOPE — stay inside CURRENT LOCATION: act within the current folder/file shown above. When the user doesn't name a folder, new notes/folders go into the CURRENT LOCATION by default. Use relative names from there; never use ".." or absolute paths.

    Examples:
    {"tool":"create_note","args":{"folder":"Projects","title":"Hello","content":"# Hello\\n\\nText."}}
    {"tool":"create_folder","args":{"name":"Archive"}}
    {"tool":"append_note","args":{"target":"Hello","content":"more text"}}
    {"tool":"read_note","args":{"target":"Meeting"}}   // STEP 1 of replace: get current text
    {"tool":"edit_note","args":{"target":"Hello","content":"new full text"}}   // rewrite / clear / apply replacement (NOT delete)
    {"tool":"delete_notes","args":{"matching":"Notes"}}   // deletes every note in folder Notes
    {"tool":"search_notes","args":{"query":"git"}}

    Tools (args keys exactly as shown, no "?"):
    create_note{folder,title,content}, create_folder{parent,name}, append_note{target,content}, edit_note{target,content},
    rename_note{target,newName}, move_note{target,toFolder}, delete_note{target}, delete_notes{matching}, delete_folder{name},
    read_note{target}, list_folder{folder}, search_notes{query}. (folder/parent are optional.)
    """

    /// Лениво извлекает первый валидный tool-JSON из ответа модели.
    /// Устойчив к вольностям слабых моделей: ключи с «?» (folder?), синонимы, грязные значения.
    public static func parse(from text: String) -> AITool? {
        guard let object = firstJSONObject(in: text) else { return nil }
        let toolName = ((object["tool"] ?? object["name"] ?? object["action"]) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        guard let tool = toolName else { return nil }

        var rawArgs = (object["args"] ?? object["arguments"] ?? object["parameters"]) as? [String: Any] ?? [:]
        if rawArgs.isEmpty {
            for (k, v) in object where !["tool", "name", "action"].contains(k.lowercased()) { rawArgs[k] = v }
        }
        var args: [String: Any] = [:]
        for (k, v) in rawArgs {
            var nk = k.trimmingCharacters(in: .whitespaces).lowercased()
            while nk.hasSuffix("?") { nk.removeLast() }
            args[nk] = v
        }
        func val(_ keys: [String]) -> String? {
            for key in keys {
                if let s = args[key] as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty, !t.contains("<"), !t.contains(">") { return t }
                }
            }
            return nil
        }
        func nameVal(_ keys: [String]) -> String? {
            guard var c = val(keys) else { return nil }
            if c.hasSuffix(".md") { c = String(c.dropLast(3)) }
            c = c.trimmingCharacters(in: CharacterSet(charactersIn: "/ \"'`"))
            return c.isEmpty ? nil : c
        }

        switch tool {
        case "create_note", "createnote", "new_note", "add_note", "write_note":
            guard let title = nameVal(["title", "name", "filename", "note"]) else { return nil }
            return .createNote(folder: nameVal(["folder", "parent", "dir", "directory", "path", "in"]),
                               title: title, content: val(["content", "text", "body", "markdown"]))
        case "create_folder", "createfolder", "new_folder", "add_folder", "make_folder":
            guard let name = nameVal(["name", "folder", "title", "dir"]) else { return nil }
            return .createFolder(parent: nameVal(["parent", "in", "path"]), name: name)
        case "delete_note", "remove_note":
            guard let target = nameVal(["target", "note", "title", "name", "path", "file"]) else { return nil }
            return .deleteNote(target: target)
        case "delete_notes", "remove_notes", "delete_all":
            guard let matching = val(["matching", "query", "pattern", "folder", "name", "target", "glob"]) else { return nil }
            return .deleteNotes(matching: matching)
        case "delete_folder", "remove_folder":
            guard let name = nameVal(["name", "folder", "target", "path"]) else { return nil }
            return .deleteFolder(name: name)
        case "search_notes", "search", "find_notes", "find":
            guard let query = val(["query", "q", "text", "matching", "term"]) else { return nil }
            return .searchNotes(query: query)
        case "list_folder", "list", "list_notes", "ls":
            return .listFolder(folder: nameVal(["folder", "path", "dir", "name"]))
        case "read_note", "read", "open_note", "get_note":
            guard let target = nameVal(["target", "note", "title", "name", "path", "file"]) else { return nil }
            return .readNote(target: target)
        case "append_note", "append", "add_to_note":
            guard let target = nameVal(["target", "note", "title", "name", "path", "file"]),
                  let content = val(["content", "text", "body", "markdown"]) else { return nil }
            return .appendNote(target: target, content: content)
        case "edit_note", "update_note", "replace_note", "set_note":
            guard let target = nameVal(["target", "note", "title", "name", "path", "file"]),
                  let content = val(["content", "text", "body", "markdown"]) else { return nil }
            return .editNote(target: target, content: content)
        case "rename_note", "rename":
            guard let target = nameVal(["target", "note", "title", "name", "path", "file", "from"]),
                  let newName = nameVal(["newname", "new_name", "to", "name", "title"]) else { return nil }
            return .renameNote(target: target, newName: newName)
        case "move_note", "move":
            guard let target = nameVal(["target", "note", "title", "name", "path", "file", "from"]),
                  let folder = nameVal(["tofolder", "to_folder", "folder", "to", "destination", "dir"]) else { return nil }
            return .moveNote(target: target, toFolder: folder)
        default:
            return nil
        }
    }

    /// Удаляет из текста любые JSON-объекты с "tool" (чтобы сырой вызов не утёк в чат).
    public static func stripToolJSON(_ text: String) -> String {
        var result = text
        while let obj = firstBalancedToolObject(in: result) {
            result.removeSubrange(obj)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Скан первого СБАЛАНСИРОВАННОГО top-level `{ … }` (с учётом строковых литералов и экранирования).
    /// На каждом полном объекте зовёт `accept(slice, start, endInclusive)`; первый НЕ-nil результат —
    /// возврат, иначе скан продолжается (start сбрасывается). Общая основа извлечения tool-JSON. Чистая фн.
    private static func firstBalancedObject<T>(in text: String, accept: (String, Int, Int) -> T?) -> T? {
        let chars = Array(text)
        var depth = 0, startIdx: Int?, inStr = false, esc = false
        for (i, c) in chars.enumerated() {
            if inStr { if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { inStr = false }; continue }
            if c == "\"" { inStr = true }
            else if c == "{" { if depth == 0 { startIdx = i }; depth += 1 }
            else if c == "}" {
                if depth > 0 { depth -= 1
                    if depth == 0, let s = startIdx {
                        if let result = accept(String(chars[s ... i]), s, i) { return result }
                        startIdx = nil
                    }
                }
            }
        }
        return nil
    }

    /// Первый сбалансированный объект, содержащий `"tool"`/`"action"` — его диапазон (для вырезания).
    private static func firstBalancedToolObject(in text: String) -> Range<String.Index>? {
        firstBalancedObject(in: text) { slice, s, i in
            guard slice.contains("\"tool\"") || slice.contains("\"action\"") else { return nil }
            return text.index(text.startIndex, offsetBy: s) ..< text.index(text.startIndex, offsetBy: i + 1)
        }
    }

    /// Первый сбалансированный `{ ... }`, который успешно парсится как JSON-объект.
    private static func firstJSONObject(in text: String) -> [String: Any]? {
        firstBalancedObject(in: text) { slice, _, _ in parseObject(slice) }
    }

    /// Парсит JSON-объект, предварительно «починив» невалидные control-символы
    /// (реальные \n,\r,\t внутри строковых литералов модель часто не экранирует).
    private static func parseObject(_ slice: String) -> [String: Any]? {
        if let data = slice.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        let repaired = escapeControlCharsInStrings(slice)
        if let data = repaired.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return nil
    }

    private static func escapeControlCharsInStrings(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + 16)
        var inString = false
        var escaped = false
        for ch in text {
            if inString {
                if escaped {
                    result.append(ch); escaped = false; continue
                }
                switch ch {
                case "\\": result.append(ch); escaped = true
                case "\"": result.append(ch); inString = false
                case "\n": result.append("\\n")
                case "\r": result.append("\\r")
                case "\t": result.append("\\t")
                default: result.append(ch)
                }
            } else {
                if ch == "\"" { inString = true }
                result.append(ch)
            }
        }
        return result
    }
}
