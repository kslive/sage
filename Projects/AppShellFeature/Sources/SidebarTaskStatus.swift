import CoreKit

/// Какой статус фоновой задачи ИИ показывать у строки дерева (чистая логика — тестируется без UI).
/// Файл: инлайн-ИИ ИЛИ чат-по-файлу. Папка: чат-по-папке. running важнее readyUnread важнее error.
@MainActor
func nodeAIPhase(_ node: FileNode, _ tasks: AITaskRegistry) -> AITaskPhase? {
    let keys: [AITaskKey] = node.isDirectory
        ? [.chat(.folder(name: "", fileCount: 0, path: node.url.path))]
        : [.inline(path: node.url.path), .chat(.file(name: "", path: node.url.path))]
    if keys.contains(where: { tasks.isRunning($0) }) { return .running }
    if keys.contains(where: { tasks.isReadyUnread($0) }) { return .readyUnread }
    if keys.contains(where: { tasks.phase($0) == .error }) { return .error }
    return nil
}
