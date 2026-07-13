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
import UpdateService
import VaultService

/// При Cmd-Q/завершении даём открытому редактору синхронно сбросить несохранённое (анти-потеря данных)
/// и применяем подготовленное OTA-обновление (если есть) после выхода (вступит в силу при следующем запуске).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .sageFlushAll, object: nil)
        UpdateService.applyPendingOnQuit()
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
    @State private var updaterVM: UpdaterViewModel
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
        _updaterVM = State(initialValue: UpdaterViewModel(updater: composition.updater, settings: settings, locale: locale))
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
                .environment(updaterVM)
                .frame(minWidth: 920, minHeight: 620)
                .sageTheme(theme)
                .onOpenURL { url in handleDeepLink(url) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: DesignSystem.windowSize.width, height: DesignSystem.windowSize.height)
        .commands { SageCommands(router: router, locale: locale, theme: theme) }

        MenuBarExtra("Sage", systemImage: "sparkle") {
            TrayMenuView(
                activeModelName: settings.activeLLM?.name ?? "—",
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

    /// Диплинк `sage://open?path=<файл>` — открыть заметку в редакторе (интеграция
    /// с внешними приложениями, например Ember). Открываем только существующий файл.
    /// Файл ВНЕ текущего пространства — переключаем пространство на его папку
    /// (сброс selectedFile в onChange(vaultPath) обходится через pendingExternalOpen).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sage", (url.host ?? "") == "open",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "path" })?.value,
              FileManager.default.fileExists(atPath: path) else { return }
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let root = settings.resolveVaultURL()?.standardizedFileURL.path ?? ""
        let inVault = !root.isEmpty && (fileURL.path == root || fileURL.path.hasPrefix(root + "/"))
        if inVault {
            router.selectedFile = fileURL
            router.go(.editor)
        } else {
            router.pendingExternalOpen = fileURL
            settings.setVault(url: fileURL.deletingLastPathComponent())
        }
        activateApp()
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
