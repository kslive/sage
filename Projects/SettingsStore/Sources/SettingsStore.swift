import CoreKit
import Foundation
import Observation
import ServiceManagement

/// Наблюдаемое хранилище настроек приложения (кроме темы/языка —
/// их держат ThemeManager/LocaleManager). Персистится в `UserDefaults`.
@Observable
public final class SettingsStore {
    public var onboardingComplete: Bool { didSet { d.set(onboardingComplete, forKey: "sage.onboarded") } }
    public var vaultBookmark: Data? { didSet { d.set(vaultBookmark, forKey: "sage.vault.bookmark") } }
    public var vaultPath: String { didSet { d.set(vaultPath, forKey: "sage.vault.path") } }
    public var activeLLMId: String { didSet { d.set(activeLLMId, forKey: "sage.model.llm") } }
    public var activeWhisperId: String? { didSet { d.set(activeWhisperId, forKey: "sage.model.whisper") } }
    public var temperature: Double { didSet { d.set(temperature, forKey: "sage.ai.temp") } }
    public var launchAtLogin: Bool {
        didSet {
            d.set(launchAtLogin, forKey: "sage.gen.launch")
            applyLaunchAtLogin()
        }
    }
    public var spellcheck: Bool { didSet { d.set(spellcheck, forKey: "sage.gen.spell") } }
    /// Сортировка файлов в сайдбаре (имя / дата изменения).
    public var sidebarSort: SidebarSort { didSet { d.set(sidebarSort.rawValue, forKey: "sage.sidebar.sort") } }
    /// Путь открытой сейчас заметки (транзиентно) — чтобы ИИ резолвил «эту/данную заметку».
    public var currentNotePath: String?
    /// Выделенный сейчас в редакторе текст (транзиентно) — чтобы ИИ видел выделение.
    public var currentSelection: String?
    public var autoSync: Bool { didSet { d.set(autoSync, forKey: "sage.git.autosync") } }
    public var gitRemote: String? { didSet { d.set(gitRemote, forKey: "sage.git.remote") } }
    public var gitFrequency: GitSyncFrequency {
        didSet { d.set(gitFrequency.rawValue, forKey: "sage.git.freq") }
    }
    /// Автоматически скачивать и устанавливать обновления в фоне.
    public var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "sage.update.auto") } }
    /// Время последней проверки обновлений (для подписи «проверено …»).
    public var lastUpdateCheck: Date? { didSet { d.set(lastUpdateCheck, forKey: "sage.update.lastcheck") } }
    /// Версия подготовленного (скачанного+проверенного) обновления, ждущего применения при выходе.
    public var pendingUpdateVersion: String? { didSet { d.set(pendingUpdateVersion, forKey: SettingsStore.pendingVersionKey) } }
    /// Путь к распакованному `.app` подготовленного обновления (staging) — применяется при выходе.
    public var pendingUpdatePath: String? { didSet { d.set(pendingUpdatePath, forKey: SettingsStore.pendingPathKey) } }

    /// Ключи pending-обновления — публичные, чтобы `applicationWillTerminate` мог применить без инстанса стора.
    public static let pendingVersionKey = "sage.update.pending.version"
    public static let pendingPathKey = "sage.update.pending.path"

    private let d: UserDefaults

    public convenience init() { self.init(defaults: .standard) }

    /// Designated-инициализатор с инъекцией хранилища — для изоляции в тестах
    /// (свой `UserDefaults(suiteName:)`, чтобы не трогать реальные настройки).
    public init(defaults: UserDefaults) {
        d = defaults
        onboardingComplete = d.bool(forKey: "sage.onboarded")
        vaultBookmark = d.data(forKey: "sage.vault.bookmark")
        vaultPath = d.string(forKey: "sage.vault.path") ?? ""
        activeLLMId = d.string(forKey: "sage.model.llm") ?? ModelCatalog.defaultLLM
        activeWhisperId = d.string(forKey: "sage.model.whisper") ?? ModelCatalog.defaultWhisper
        temperature = d.object(forKey: "sage.ai.temp") as? Double ?? 0.7
        launchAtLogin = d.object(forKey: "sage.gen.launch") as? Bool ?? true
        spellcheck = d.object(forKey: "sage.gen.spell") as? Bool ?? true
        sidebarSort = d.string(forKey: "sage.sidebar.sort").flatMap(SidebarSort.init(rawValue:)) ?? .name
        autoSync = d.object(forKey: "sage.git.autosync") as? Bool ?? true
        gitRemote = d.string(forKey: "sage.git.remote")
        gitFrequency = d.string(forKey: "sage.git.freq").flatMap(GitSyncFrequency.init(rawValue:)) ?? .onChange
        autoUpdate = d.object(forKey: "sage.update.auto") as? Bool ?? true
        lastUpdateCheck = d.object(forKey: "sage.update.lastcheck") as? Date
        pendingUpdateVersion = d.string(forKey: SettingsStore.pendingVersionKey)
        pendingUpdatePath = d.string(forKey: SettingsStore.pendingPathKey)
    }

    /// Активная LLM как спецификация каталога.
    public var activeLLM: LLMModelSpec? { ModelCatalog.llm(id: activeLLMId) }
    public var activeWhisper: WhisperModelSpec? { activeWhisperId.flatMap(ModelCatalog.whisper(id:)) }

    /// Разрешённый URL хранилища. Приложение не сэндбоксится (неподписанная
    /// локальная сборка), поэтому используем обычные bookmarks.
    public func resolveVaultURL() -> URL? {
        if let data = vaultBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return vaultPath.isEmpty ? nil : URL(fileURLWithPath: vaultPath)
    }

    public func setVault(url: URL) {
        vaultBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        vaultPath = url.path
    }

    /// Регистрация приложения как login item (реально включает «Запуск при входе»).
    public func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
        }
    }
}
