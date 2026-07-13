import CoreKit
import Foundation
import Observation

/// Глобальное состояние навигации и оболочки приложения.
@MainActor
@Observable
public final class AppRouter {
    public var view: AppView = .editor
    public var selectedFile: URL?
    public var sidebarOpen = true
    public var searchOpen = false
    public var settingsTab: SettingsTab = .general

    public var editorMode: EditorMode = .preview
    public var editorVariant: EditorVariant = .a

    /// Запрос на вызов инлайн-ИИ в редакторе (из меню ИИ / ⌘J). nonce — для пере-триггера.
    public var inlineAINonce = 0
    public func invokeInlineAI() { inlineAINonce += 1 }

    /// Запрос на удаление текущей открытой заметки (из меню / ⌘⌫, когда дерево не в фокусе).
    public var deleteSelectedNonce = 0
    public func requestDeleteSelected() { deleteSelectedNonce += 1 }

    /// Контекст, с которым открыть чат (устанавливается из сайдбара/редактора).
    public var pendingChatContext: ChatContext?
    /// Запрос, который надо сразу отправить в чат (из поиска). nonce — для пере-триггера.
    public var pendingChatPrompt: String?
    public var chatPromptNonce = 0

    /// Файл, который надо открыть ПОСЛЕ смены хранилища (диплинк на заметку вне
    /// текущего пространства): смена vaultPath сбрасывает selectedFile, поэтому
    /// открытие откладывается до обработчика onChange(vaultPath) в RootView.
    public var pendingExternalOpen: URL?

    public init() {}

    public func go(_ view: AppView) {
        self.view = view
    }

    public func openChat(context: ChatContext) {
        pendingChatContext = context
        pendingChatPrompt = nil
        view = .chat
    }

    /// Открыть чат по всему хранилищу и сразу отправить запрос (из поиска).
    public func askVault(query: String) {
        pendingChatContext = .vault
        pendingChatPrompt = query
        chatPromptNonce += 1
        view = .chat
    }

    public func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        view = .settings
    }

    public func toggleSidebar() {
        sidebarOpen.toggle()
    }
}
