import AppShellFeature
import DesignSystem
import Localization
import SwiftUI

/// Нативное главное меню macOS (локализованное).
struct SageCommands: Commands {
    let router: AppRouter
    let locale: LocaleManager
    let theme: ThemeManager

    private var s: Strings { locale.strings }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(s.menu.find) { router.searchOpen = true }
                .keyboardShortcut("f", modifiers: .command)
            Button(s.common.delete) { router.requestDeleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(router.selectedFile == nil)
        }
        CommandGroup(replacing: .sidebar) {
            Button(s.menu.toggleSidebar) { router.toggleSidebar() }
                .keyboardShortcut("s", modifiers: .command)
            Button(s.menu.cycleTheme) { theme.cycle() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .appSettings) {
            Button(s.menu.settings) { router.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu(s.menu.goMenu) {
            Button(s.menu.editorView) { router.go(.editor) }.keyboardShortcut("1", modifiers: .command)
            Button(s.menu.chatView) { router.go(.chat) }.keyboardShortcut("2", modifiers: .command)
            Button(s.menu.settingsView) { router.openSettings() }.keyboardShortcut("3", modifiers: .command)
        }
        CommandMenu(s.menu.aiMenu) {
            Button(s.menu.askSage) { router.go(.editor); router.invokeInlineAI() }
                .keyboardShortcut("j", modifiers: .command)
        }
    }
}
