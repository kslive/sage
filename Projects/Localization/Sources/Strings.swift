import CoreKit
import Foundation

/// Полный набор строк интерфейса. Экземпляры (ru/en/zh) строятся внутри модуля
/// через синтезированный memberwise-init; наружу видны как `Strings.ru/.en/.zh`.
public struct Strings: Sendable {
    public let brandTagline: String
    public let common: Common
    public let ob: Onboarding
    public let nav: Nav
    public let app: App
    public let chat: Chat
    public let search: Search
    public let settings: Settings
    public let theme: Theme
    public let tray: Tray
    public let menu: Menu
    public let models: Models
    public let slash: Slash
    public let toast: Toast
    public let git: Git

    public struct Common: Sendable {
        public let back, cancel, delete, change, justNow: String
    }

    public struct Onboarding: Sendable {
        public let langTitle, langSub: String
        public let stepFolder, folderTitle, folderSub, chooseFolder, folderHint, folderPicked, privacyNote: String
        public let stepModel, modelTitle, modelSub, recommended: String
        public let stepWhisper, whisperTitle, whisperSub: String
        public let stepDownload, downloading, verifying, dlDone, dlErrorMsg, retry: String
        public let readyTitle, readySub: String
        public let continueAction, openSage: String
        public let stageModel, stageWhisper, stageOnlyModel, downloadContinue: String
        public let speedUnit: String
    }

    public struct Nav: Sendable {
        public let search, editor, chat: String
    }

    public struct App: Sendable {
        public let files, localRunning, outline, info, words, edited: String
        public let askInline: String
        public let aiThinking, aiImproving, aiContinuing, aiSummarizing: String
        public let aiApplied, aiFailed: String
        public let newNote, openFolder, emptyVaultTitle, emptyVaultBody: String
        public let newNoteName: String
        public let noSelectionTitle, noSelectionBody: String
        public let newFolder, rename, open, deleteFolder: String
        public let sortBy, sortByName, sortByModified: String
        public let copyPath, copied: String
        public let ready: String
    }

    public struct Chat: Sendable {
        public let title, placeholder: String
        public let perm, transcribing, errorMsg, retry, stopGen: String
        public let voiceTitle, voiceHint, voiceCancel, voiceConfirm: String
        public let history, historyHeader, ctxVault, ctxSelection, clearChat: String
        public let deletePrompt, deleted: String
        public let askTitle, askBody, copy: String
        public let suggest1, suggest2, suggest3: String
        public let histToday, histYesterday, histEarlier: String
        public let histEmptyTitle, histEmptyBody: String
    }

    public struct Search: Sendable {
        public let placeholder, noResults, askSub, searching, recent, results, askPrefix: String
    }

    public struct Settings: Sendable {
        public let title, general, ai, appearance, git, about: String
        public let generalSub, language, languageSub, vault, change, startup, startupSub, spellcheck, spellcheckSub: String
        public let aiSub, llmSection, whisperSection, download: String
        public let appearanceSub, theme, accent, accentSub: String
        public let gitSub, gitConnectTitle, gitConnectSub, gitConnect, branch, lastSync, synced, disconnect, gitTokenHint: String
        public let autoSync, autoSyncSub, syncFrequency, syncFrequencySub: String
        public let freqOnChange, freqEvery5, freqHourly, freqManual, recentCommits, syncNow, syncing: String
        public let version, chipLocal, chipSilicon, chipMarkdown: String
        public let updates, updatesSub, upToDate, checkingUpdates, installingUpdate, checkUpdates, checkNow, lastChecked: String
        public let updateAvailable, updateNow, downloadingUpdate, updateReady, restartNow, updateFailed, retryUpdate: String
        public let autoUpdate, autoUpdateSub, youHaveVersion: String
        public let updateReadyTitle, updateAvailableTitle, openAction: String
        public let updateErrNetwork, updateErrChecksum, updateErrNoApp, updateErrInstall, downloadIncomplete: String
    }

    public struct Theme: Sendable {
        public let dark, light, auto: String
    }

    public struct Tray: Sendable {
        public let statusRunning, newChat, search, settings, quit: String
    }

    public struct Menu: Sendable {
        public let edit, goMenu: String
        public let find, toggleSidebar, settings: String
        public let editorView, chatView, settingsView, cycleTheme: String
        public let aiMenu, askSage: String
    }

    /// Описания моделей (имена — из каталога, тут — пояснения/RAM).
    public struct Models: Sendable {
        public let descSmall, descMid, descLarge: String
        public let ramSmall, ramMid, ramLarge: String
        public let whisperBaseDesc, whisperSmallDesc, whisperTinyDesc, whisperTurboDesc: String
        public let whisperNone, whisperNoneDesc: String
        public let notInstalled, active, installed, downloadingStatus: String
    }

    public struct Slash: Sendable {
        public let aiAsk: String
        public let linkURL, linkNote, linkText, linkAdd, linkCreate: String
        public let blkText, blkH1, blkH2, blkH3, blkBullet, blkNumbered, blkCheck: String
        public let blkQuote, blkTable, blkCode, blkDivider, blkLink, tableColumn: String
    }

    public struct Toast: Sendable {
        public let folderOpened: String
        public let aiReplied: String
    }

    /// Git: глаголы для сообщений коммитов + локализованные статусы синхронизации (тосты).
    public struct Git: Sendable {
        public let commitAutoSync, commitMerge: String
        public let syncUpToDate, syncPushed, syncConflict: String
        public let syncNoRepo, syncUnrelated, connectConflict: String
    }
}

/// Локализованный тост для результата синхронизации. КОДЫ `GitSyncOutcome` → текст на языке UI
/// (чтобы статус не вылезал на английском). `.failed(reason:)` — сырой git stderr, показываем как есть.
public func gitSyncToast(_ outcome: GitSyncOutcome, _ s: Strings) -> (icon: String, text: String, isError: Bool) {
    switch outcome {
    case let .synced(pushed): ("✓", "\(s.git.syncPushed) · \(pushed)", false)
    case .upToDate: ("✓", s.git.syncUpToDate, false)
    case let .conflict(file): ("⚠️", "\(s.git.syncConflict) · \(file)", true)
    case .noRepo: ("⚠️", s.git.syncNoRepo, true)
    case .unrelatedHistories: ("⚠️", s.git.syncUnrelated, true)
    case let .failed(reason): ("⚠️", reason, true)
    }
}
