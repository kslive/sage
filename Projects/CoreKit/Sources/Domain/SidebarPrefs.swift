import Foundation

/// Режим сортировки списка файлов в сайдбаре.
public enum SidebarSort: String, Sendable, CaseIterable, Codable {
    case name
    case modified
}

/// Упорядочить набор узлов: сначала папки, затем файлы; внутри группы — по выбранному ключу
/// (имя А–Я или дата изменения, новые сверху). Чистая функция (тестируется без UI).
public func sortedFileNodes(_ nodes: [FileNode], by sort: SidebarSort) -> [FileNode] {
    func ordered(_ items: [FileNode]) -> [FileNode] {
        switch sort {
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modified:
            return items.sorted {
                let l = $0.effectiveModified ?? .distantPast, r = $1.effectiveModified ?? .distantPast
                if l == r { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return l > r
            }
        }
    }
    return ordered(nodes.filter(\.isDirectory)) + ordered(nodes.filter { !$0.isDirectory })
}

public extension FileNode {
    /// Сколько `.md`-заметок внутри (рекурсивно) — для счётчика у папки («· 9 файлов»).
    var mdCount: Int {
        children.reduce(0) { $0 + ($1.isDirectory ? $1.mdCount : 1) }
    }

    /// Дети, упорядоченные для отображения (делегирует в `sortedFileNodes`).
    func sortedChildren(by sort: SidebarSort) -> [FileNode] {
        sortedFileNodes(children, by: sort)
    }

    /// Самая свежая дата изменения в субдереве (для сортировки папок по дате): max собственной
    /// mtime и mtime всех потомков. Файл → собственная mtime.
    var effectiveModified: Date? {
        var best = modifiedAt
        for child in children {
            guard let c = child.effectiveModified else { continue }
            if let b = best { if c > b { best = c } } else { best = c }
        }
        return best
    }
}

/// Id всех папок-ПРЕДКОВ узла `id` в дереве `nodes` (которые надо раскрыть, чтобы узел стал виден).
/// Узел верхнего уровня → []. Сам узел в результат НЕ входит. Чистая логика (тест сайдбар-хайлайта).
public func sidebarAncestorFolderIDs(of id: String, in nodes: [FileNode]) -> [String] {
    var acc: [String] = []
    @discardableResult
    func walk(_ items: [FileNode]) -> Bool {
        for n in items {
            if n.id == id { return true }
            if n.isDirectory, walk(n.children) { acc.append(n.id); return true }
        }
        return false
    }
    walk(nodes)
    return acc
}

/// Резервировать ли фикс-слот статуса в строке сайдбара (для стабильного размера по фазам ИИ):
/// если есть фоновая задача ИЛИ это папка со счётчиком. Чистая логика (тест стабильности размера).
public func sidebarReservesStatusSlot(hasTask: Bool, isDirectory: Bool, mdCount: Int) -> Bool {
    hasTask || (isDirectory && mdCount > 0)
}

/// Показывать ли ✦-«спросить» на hover строки. ТОЛЬКО когда задачи НЕТ: при running/готово индикатор
/// задачи остаётся видимым и кликабельным (→ вернуться к инлайн-ответу/чату), иначе hover подменял его
/// на ✦ и клик уводил в ЧАТ вместо инлайн-ответа. Чистая логика (тест инлайн-навигации). [[apptests-mlx-bootstrap]]
public func sidebarShowsHoverAsk(hovering: Bool, isRenaming: Bool, hasTask: Bool) -> Bool {
    hovering && !isRenaming && !hasTask
}
