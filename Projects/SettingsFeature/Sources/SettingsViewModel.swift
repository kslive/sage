import CoreKit
import Foundation
import GitService
import Localization
import Observation
import SettingsStore

@MainActor
@Observable
public final class SettingsViewModel {
    public var modelStates: [String: DownloadState] = [:]
    public var gitInfo: GitRepoInfo?
    public var commits: [GitCommit] = []
    public var remoteInput = ""
    public var tokenInput = ""
    public var gitSyncing = false
    /// Текущие строки UI (синхронизируются из View по смене языка) — для локализованных тостов/коммитов.
    public var strings: Strings = .ru

    private let models: ModelManaging
    private let git: GitServicing
    private let settings: SettingsStore
    private let onToast: (String, String, Bool) -> Void
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    public init(
        models: ModelManaging, git: GitServicing, settings: SettingsStore,
        onToast: @escaping (String, String, Bool) -> Void
    ) {
        self.models = models
        self.git = git
        self.settings = settings
        self.onToast = onToast
    }

    public func loadStates() async {
        for spec in ModelCatalog.llms {
            if await models.isDownloading(spec.id) { subscribeLLM(spec) }
            else { modelStates[spec.id] = await models.stateForLLM(spec.id) }
        }
        for spec in ModelCatalog.whispers {
            if await models.isDownloading(spec.id) { subscribeWhisper(spec) }
            else { modelStates[spec.id] = await models.stateForWhisper(spec.id) }
        }
    }

    public func state(_ id: String) -> DownloadState { modelStates[id] ?? .notInstalled }

    public func downloadLLM(_ spec: LLMModelSpec) { subscribeLLM(spec) }
    public func downloadWhisper(_ spec: WhisperModelSpec) { subscribeWhisper(spec) }

    private func subscribeLLM(_ spec: LLMModelSpec) {
        downloadTasks[spec.id]?.cancel()
        downloadTasks[spec.id] = Task { [weak self] in
            guard let self else { return }
            for await state in models.downloadLLM(spec) {
                modelStates[spec.id] = state
                if state.isInstalled { onToast("✓", spec.name, false) }
            }
        }
    }

    private func subscribeWhisper(_ spec: WhisperModelSpec) {
        downloadTasks[spec.id]?.cancel()
        downloadTasks[spec.id] = Task { [weak self] in
            guard let self else { return }
            for await state in models.downloadWhisper(spec) {
                modelStates[spec.id] = state
                if state.isInstalled { onToast("✓", spec.name, false) }
            }
        }
    }

    public func activateLLM(_ id: String) { settings.activeLLMId = id }
    public func activateWhisper(_ id: String) { settings.activeWhisperId = id }

    /// Удалить скачанную LLM с диска. Если удалили активную — переключиться на любую другую
    /// установленную (иначе ИИ молча «не готов»); без установленных активная остаётся (карточка «Скачать»).
    public func deleteLLM(_ spec: LLMModelSpec) {
        Task {
            await models.deleteLLM(spec.id)
            modelStates[spec.id] = .notInstalled
            if settings.activeLLMId == spec.id, let fallback = await models.installedLLMs().first {
                settings.activeLLMId = fallback
            }
            onToast("🗑", spec.name, false)
        }
    }

    public func deleteWhisper(_ spec: WhisperModelSpec) {
        Task {
            await models.deleteWhisper(spec.id)
            modelStates[spec.id] = .notInstalled
            if settings.activeWhisperId == spec.id {
                settings.activeWhisperId = await models.installedWhispers().first
            }
            onToast("🗑", spec.name, false)
        }
    }

    // MARK: - Git

    public func loadGit() async {
        guard let url = settings.resolveVaultURL() else { return }
        gitInfo = await git.info(at: url)
        commits = await git.recentCommits(at: url, limit: 5)
    }

    public func connectGit() {
        guard let url = settings.resolveVaultURL(), !remoteInput.isEmpty else { return }
        SecretStore.set(tokenInput.isEmpty ? nil : tokenInput, account: SecretStore.gitTokenAccount(for: url.path))
        gitSyncing = true
        NotificationCenter.default.post(name: .sageFlushAll, object: nil)
        NotificationCenter.default.post(name: .sageGitSyncBegan, object: nil)
        let mergeMsg = Formatting.gitCommitMessage(action: strings.git.commitMerge, date: Date())
        Task {
            var errorText: String?
            do {
                try await git.connect(remote: remoteInput, at: url, mergeMessage: mergeMsg)
            } catch let GitError.connectConflict(file) {
                errorText = "\(strings.git.connectConflict): \(file)"
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            settings.gitRemote = remoteInput
            tokenInput = ""
            gitSyncing = false
            await loadGit()
            NotificationCenter.default.post(name: .sageGitSynced, object: nil)
            if let errorText { onToast("⚠️", errorText, true) } else { onToast("✓", remoteInput, false) }
        }
    }

    public func syncNow() {
        guard let url = settings.resolveVaultURL() else { return }
        gitSyncing = true
        /// Флаш до коммита (иначе уйдёт устаревшая дисковая версия) + сигнал редактору
        /// отложить дебаунс-сейвы до `.sageGitSynced` (запись посреди rebase разрушительна).
        NotificationCenter.default.post(name: .sageFlushAll, object: nil)
        NotificationCenter.default.post(name: .sageGitSyncBegan, object: nil)
        let message = Formatting.gitCommitMessage(action: strings.git.commitAutoSync, date: Date())
        Task {
            let outcome = await git.sync(at: url, message: message)
            gitSyncing = false
            await loadGit()
            NotificationCenter.default.post(name: .sageGitSynced, object: nil)
            let t = gitSyncToast(outcome, strings)
            onToast(t.icon, t.text, t.isError)
        }
    }

    public func disconnectGit() {
        guard let url = settings.resolveVaultURL() else { return }
        Task {
            await git.disconnect(at: url)
            SecretStore.set(nil, account: SecretStore.gitTokenAccount(for: url.path))
            settings.gitRemote = nil
            gitInfo = nil
            commits = []
        }
    }

    /// «Подключено» — есть remote (а не просто локальный git-репозиторий),
    /// иначе после «Отключить» (remote снят, но .git остаётся) экран снова показывал подключение.
    public var isGitConnected: Bool {
        if let remote = gitInfo?.remoteURL, remote != "—", !remote.isEmpty { return true }
        return settings.gitRemote != nil
    }
}
