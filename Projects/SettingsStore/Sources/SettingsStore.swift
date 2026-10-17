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
    /// Id модели DeepSeek, выбранной из GET /models ЭТОГО ключа ("" = не выбрана → облако выключено).
    public var deepseekModel: String { didSet { d.set(deepseekModel, forKey: "sage.deepseek.model") } }
    /// Реактивное зеркало наличия DeepSeek-ключа (сам SecretStore-файл не наблюдаем) —
    /// статус-лейблы («работает локально» ↔ «облако DeepSeek») обновляются мгновенно.
    public private(set) var deepseekConnected = false
    /// Последняя облачная генерация упала (сеть/ключ) — ответила локальная модель. Транзиентный
    /// флаг (не персистится): лейблы честно показывают локальный режим; успешный облачный ответ снимает.
    public var cloudAIDown = false

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
        deepseekModel = d.string(forKey: "sage.deepseek.model") ?? ""
        deepseekConnected = SettingsStore.deepseekKey() != nil
    }

    /// DeepSeek API-ключ (device-bound шифрованный файл — см. SecretStore). nil = облако выключено.
    public static func deepseekKey() -> String? {
        let v = SecretStore.get(account: SecretStore.deepseekKeyAccount) ?? ""
        return v.isEmpty ? nil : v
    }

    public func setDeepseekKey(_ key: String) {
        SecretStore.set(key, account: SecretStore.deepseekKeyAccount)
        deepseekConnected = true
        cloudAIDown = false
    }

    public func deleteDeepseekKey() {
        SecretStore.delete(account: SecretStore.deepseekKeyAccount)
        deepseekModel = ""
        deepseekConnected = false
        cloudAIDown = false
    }

    /// Облако — активный движок ИИ (для статус-лейблов): ключ подключён, модель выбрана и облако живо.
    public var cloudAIActive: Bool { deepseekConnected && !deepseekModel.isEmpty && !cloudAIDown }

    /// Активная LLM как спецификация каталога.
    public var activeLLM: LLMModelSpec? { ModelCatalog.llm(id: activeLLMId) }
    public var activeWhisper: WhisperModelSpec? { activeWhisperId.flatMap(ModelCatalog.whisper(id:)) }

    /// Хранилище, к которому уже открыт sandbox-доступ (держим до выхода из приложения).
    @ObservationIgnored private var vaultAccessURL: URL?

    /// Разрешённый URL хранилища. Приложение в App Sandbox: папка из NSOpenPanel
    /// доступна только до выхода, после перезапуска — лишь через security-scoped
    /// bookmark. Резолвим его один раз, открываем доступ и обновляем протухший bookmark.
    public func resolveVaultURL() -> URL? {
        if let url = vaultAccessURL { return url }
        if let data = vaultBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                if stale { vaultBookmark = Self.securityScopedBookmark(for: url) }
                vaultAccessURL = url
                return url
            }
        }
        return vaultPath.isEmpty ? nil : URL(fileURLWithPath: vaultPath)
    }

    /// `url` должен быть выдан пользователем (NSOpenPanel) — иначе sandbox не даст создать bookmark.
    public func setVault(url: URL) {
        vaultAccessURL?.stopAccessingSecurityScopedResource()
        vaultAccessURL = nil
        vaultBookmark = Self.securityScopedBookmark(for: url)
        vaultPath = url.path
    }

    private static func securityScopedBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
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
