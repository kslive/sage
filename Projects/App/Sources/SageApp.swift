import AppShellFeature
import CoreKit
import DesignSystem
import InferenceService
import Localization
import ModelService
import OnboardingFeature
import SettingsFeature
import SettingsStore
import SwiftUI
import VaultService

/// При Cmd-Q/завершении даём открытому редактору синхронно сбросить несохранённое (анти-потеря данных).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .sageFlushAll, object: nil)
    }
}

@main
struct SageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var theme: ThemeManager
    @State private var locale: LocaleManager
    @State private var settings: SettingsStore
    @State private var router = AppRouter()
    @State private var toasts = ToastCenter()
    @State private var tasks = AITaskRegistry()
    private let composition: AppComposition

    init() {
        FreshInstallGuard.resetIfNewBuild()
        SageFonts.registerIfNeeded()
        let theme = ThemeManager()
        let locale = LocaleManager()
        let settings = SettingsStore()
        _theme = State(initialValue: theme)
        _locale = State(initialValue: locale)
        _settings = State(initialValue: settings)
        settings.applyLaunchAtLogin()
        let vault = VaultService()
        let ai = RealAICoordinator(
            inference: InferenceService(),
            models: ModelService.shared,
            settings: settings,
            locale: locale,
            vault: vault
        )
        composition = AppComposition.make(ai: ai, vault: vault)
    }

    var body: some Scene {
        WindowGroup {
            RootView(composition: composition)
                .environment(theme)
                .environment(locale)
                .environment(settings)
                .environment(router)
                .environment(toasts)
                .environment(tasks)
                .frame(minWidth: 920, minHeight: 620)
                .sageTheme(theme)
                .onOpenURL { url in handleDeepLink(url) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: DesignSystem.windowSize.width, height: DesignSystem.windowSize.height)
        .commands { SageCommands(router: router, locale: locale, theme: theme) }

        MenuBarExtra("Sage", systemImage: "sparkle") {
            TrayMenuView(
                activeModelName: settings.cloudAIActive ? settings.deepseekModel : (settings.activeLLM?.name ?? "—"),
                cloudAI: settings.cloudAIActive,
                ready: settings.onboardingComplete,
                onNewChat: { trayAction { router.openChat(context: .vault) } },
                onSearch: { trayAction { router.searchOpen = true } },
                onSettings: { trayAction { router.openSettings() } },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .environment(theme)
            .environment(locale)
            .environment(router)
            .sageTheme(theme)
        }
        .menuBarExtraStyle(.window)
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Диплинк `sage://open?path=<файл>[&root=<корень>]` — открыть заметку в
    /// редакторе (интеграция с внешними приложениями, например Ember). Открываем
    /// только существующий файл. Файл ВНЕ текущего пространства — переключаем
    /// пространство: на `root`, если он передан, существует и содержит файл
    /// (Ember раскладывает экспорт по подпапкам дат — без `root` пространством
    /// стала бы голая папка даты вместо волта), иначе на папку файла. Под App Sandbox
    /// доступ к такой папке даёт только пользователь — подтверждаем её в панели. Сброс
    /// selectedFile в onChange(vaultPath) обходится через pendingExternalOpen.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sage", (url.host ?? "") == "open",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "path" })?.value,
              FileManager.default.fileExists(atPath: path) else { return }
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let root = settings.resolveVaultURL()?.standardizedFileURL.path ?? ""
        let inVault = !root.isEmpty && (fileURL.path == root || fileURL.path.hasPrefix(root + "/"))
        activateApp()
        if inVault {
            router.selectedFile = fileURL
            router.go(.editor)
        } else {
            guard let granted = requestFolderAccess(proposed: externalVaultRoot(for: fileURL, comps: comps)),
                  fileURL.path.hasPrefix(granted.standardizedFileURL.path + "/") else { return }
            router.pendingExternalOpen = fileURL
            settings.setVault(url: granted)
        }
    }

    /// Панель выбора папки, открытая на `proposed`: под App Sandbox папка вне
    /// хранилища становится доступной только после явного выбора пользователем.
    private func requestFolderAccess(proposed: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = proposed
        panel.prompt = locale.strings.ob.chooseFolder
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Корень пространства для внешнего файла: валидный `root`-параметр,
    /// содержащий файл, побеждает; фолбэк — родительская папка файла.
    private func externalVaultRoot(for fileURL: URL, comps: URLComponents) -> URL {
        guard let rootParam = comps.queryItems?.first(where: { $0.name == "root" })?.value else {
            return fileURL.deletingLastPathComponent()
        }
        let rootURL = URL(fileURLWithPath: rootParam).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue,
              fileURL.path.hasPrefix(rootURL.path + "/") else {
            return fileURL.deletingLastPathComponent()
        }
        return rootURL
    }

    /// Выполнить действие из трея и закрыть дропдаун MenuBarExtra.
    private func trayAction(_ action: () -> Void) {
        action()
        dismissTray()
        activateApp()
    }

    private func dismissTray() {
        for window in NSApplication.shared.windows
        where String(describing: type(of: window)).contains("MenuBarExtra") {
            window.close()
        }
    }
}
