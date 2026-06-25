import Foundation

/// Событие потока ответа ассистента (текст или действие над хранилищем).
public enum AssistantEvent: Sendable {
    case token(String)
    /// Выполненное действие (детерминированное подтверждение для UI).
    case action(summary: String)
    /// Предложение удалить заметку — требует подтверждения пользователя.
    case proposeDeletion(path: String, title: String)
}

/// Уведомление об изменении файлов хранилища (создание/удаление/перемещение) — UI перезагружает дерево.
public extension Notification.Name {
    static let sageVaultChanged = Notification.Name("sage.vault.changed")
    /// Постится при завершении приложения — открытый редактор синхронно сбрасывает несохранённое.
    static let sageFlushAll = Notification.Name("sage.flushAll")
    /// Сессия чата удалена из стора (object: ChatContext удалённой беседы) — App инвалидирует
    /// keep-alive VM этого контекста, чтобы переоткрытие не показало старые сообщения из памяти.
    static let sageChatSessionDeleted = Notification.Name("sage.chat.sessionDeleted")
    /// Git-синхронизация завершена (ручная или авто): дерево перечитывается, открытый файл
    /// сверяется с диском (подтянутая версия не теряется). Отдельно от vaultChanged — нет петли auto-sync.
    static let sageGitSynced = Notification.Name("sage.git.synced")
    /// Локальная правка записана на диск редактором (FSEvents игнорирует свои записи) — триггер
    /// onChange-авто-sync (push). Не вызывает рефреш дерева/файла → не путается с pull-потоком.
    static let sageLocalEdit = Notification.Name("sage.local.edit")
}
