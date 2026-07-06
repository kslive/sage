import AppKit
import AppShellFeature
import ChatFeature
import Combine
import CoreKit
import DesignSystem
import EditorFeature
import Localization
import OnboardingFeature
import SearchFeature
import SettingsFeature
import SettingsStore
import SwiftUI
import VaultService

/// Развилка: онбординг или основное окно.
struct RootView: View {
    let composition: AppComposition
    @Environment(SettingsStore.self) private var settings
    @Environment(LocaleManager.self) private var locale
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if settings.onboardingComplete {
                MainShellView(composition: composition)
            } else {
                OnboardingView(models: composition.models, settings: settings, locale: locale) {}
            }
        }
        .background(palette.bg)
        .ignoresSafeArea()
    }
}

/// Основное окно: сайдбар + главная колонка + тосты.
struct MainShellView: View {
    let composition: AppComposition

    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(LocaleManager.self) private var locale
    @Environment(ThemeManager.self) private var theme
    @Environment(ToastCenter.self) private var toasts
    @Environment(AITaskRegistry.self) private var tasks
    @Environment(\.palette) private var palette

    @State private var expanded: Set<String> = []
    @State private var tree: [FileNode] = []
    @State private var watcher = VaultWatcher()
    @State private var treeReloadTask: Task<Void, Never>?
    @State private var whisperURL: URL?
    @State private var pendingFolderDelete: FileNode?
    @AppStorage("sage.sidebarWidth") private var sidebarWidthRaw: Double = 246
    @State private var renamingID: String?
    @State private var chatOpened = false
    /// Постоянные VM чата по контексту — генерация живёт при навигации/смене контекста.
    @State private var chatVMs: [String: ChatViewModel] = [:]
    /// Дебаунс двойного создания: macOS `Menu { Button }` дёргает экшен дважды на один клик.
    @State private var lastCreateAt = Date.distantPast
    private func canCreate() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastCreateAt) > 0.8 else { return false }
        lastCreateAt = now
        return true
    }
    /// Подтверждение удаления файла (ⓘ как у папки — больше не «тупо удаляет»).
    @State private var pendingFileDelete: FileNode?
    /// Текущий курсор/фокус дерева — чтобы ⌘⌫ из меню удалял именно выбранное в дереве (файл/папку).
    @State private var treeCursorNode: FileNode?
    @State private var treeIsFocused = false
    /// ⌘⌫ при фокусе дерева → бамп; сайдбар ловит и удаляет мультивыбор/курсор (с алертом).
    @State private var treeDeleteNonce = 0

    @State private var gitSyncInFlight = false
    @State private var gitPeriodicTask: Task<Void, Never>?
    @State private var gitChangeDebounce: Task<Void, Never>?
    @State private var lastGitSyncAt = Date.distantPast

    @Environment(UpdaterViewModel.self) private var updaterVM
    @State private var updatePeriodicTask: Task<Void, Never>?

    private var s: Strings { locale.strings }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if router.sidebarOpen {
                    SidebarView(
                        workspaceName: workspaceName,
                        vaultPath: settings.vaultPath.isEmpty ? "~/Documents/vault" : abbreviated(settings.vaultPath),
                        tree: tree,
                        expanded: $expanded,
                        selectedFileID: highlightedFileID,
                        activeModelName: settings.activeLLM?.name ?? "—",
                        sort: settings.sidebarSort,
                        renamingID: $renamingID,
                        deleteNonce: treeDeleteNonce,
                        actions: actions
                    )
                    .frame(width: CGFloat(sidebarWidthRaw))
                    .overlay(alignment: .trailing) {
                        ResizeHandle(width: Binding(get: { CGFloat(sidebarWidthRaw) }, set: { sidebarWidthRaw = Double($0) }), min: 200, max: 380)
                    }
                    .transition(.move(edge: .leading))
                }
                mainColumn
            }
            if router.searchOpen {
                SearchView(
                    vault: composition.vault,
                    markdown: composition.markdown,
                    rootURL: settings.resolveVaultURL(),
                    onClose: { router.searchOpen = false },
                    onOpen: { url in
                        router.selectedFile = url
                        router.go(.editor)
                        router.searchOpen = false
                    },
                    onAsk: { query in
                        router.searchOpen = false
                        let q = query.trimmingCharacters(in: .whitespaces)
                        if q.isEmpty { router.openChat(context: .vault) } else { router.askVault(query: q) }
                    }
                )
                .transition(.opacity)
            }
            ToastHost(toasts) { route in openTaskRoute(route) }
        }
        .animation(SageMotion.smooth, value: router.sidebarOpen)
        .animation(SageMotion.fade, value: router.searchOpen)
        .alert(
            s.app.deleteFolder,
            isPresented: Binding(get: { pendingFolderDelete != nil }, set: { if !$0 { pendingFolderDelete = nil } }),
            presenting: pendingFolderDelete
        ) { node in
            Button(s.app.deleteFolder, role: .destructive) { performDelete(node) }
                .keyboardShortcut(.defaultAction)
            Button(s.common.cancel, role: .cancel) {}
        } message: { node in
            Text("«\(node.name)»")
        }
        .alert(
            s.common.delete,
            isPresented: Binding(get: { pendingFileDelete != nil }, set: { if !$0 { pendingFileDelete = nil } }),
            presenting: pendingFileDelete
        ) { node in
            Button(s.common.delete, role: .destructive) { performDelete(node) }
                .keyboardShortcut(.defaultAction)
            Button(s.common.cancel, role: .cancel) {}
        } message: { node in
            Text("«\(node.name)»")
        }
        .task {
            router.searchOpen = false
            if let id = settings.activeWhisperId {
                whisperURL = await composition.models.localURLForWhisper(id)
            }
            await loadTree()
            startWatching()
            refreshGitBinding()
            await runAutoSync()
            updaterVM.checkInBackground()
            startUpdatePoll()
        }
        .onChange(of: updaterVM.phase) { _, phase in handleUpdatePhase(phase) }
        .onChange(of: whisperURL) { _, url in
            for vm in chatVMs.values { vm.updateWhisper(url) }
        }
        .onChange(of: router.selectedFile) { _, file in
            settings.currentNotePath = file?.path
        }
        .onChange(of: settings.vaultPath) { _, _ in
            startWatching()
            router.selectedFile = nil
            router.pendingChatContext = nil
            router.searchOpen = false
            pendingFileDelete = nil
            pendingFolderDelete = nil
            renamingID = nil
            chatVMs.removeAll()
            chatOpened = false
            expanded.removeAll()
            tasks.prune { _ in false }
            toasts.dismiss()
            lastGitSyncAt = .distantPast
            router.go(.editor)
            refreshGitBinding()
            startGitAutoSync()
            Task { await loadTree() }
        }
        .onChange(of: settings.autoSync) { _, _ in startGitAutoSync() }
        .onChange(of: settings.gitFrequency) { _, _ in startGitAutoSync() }
        .onReceive(NotificationCenter.default.publisher(for: .sageVaultChanged)) { note in
            Task {
                await loadTree()
                if let url = note.userInfo?["url"] as? URL,
                   (note.userInfo?["created"] as? Bool) == true {
                    router.selectedFile = url
                }
                pruneDeletedContexts()
                pruneTasks()
            }
            scheduleOnChangeSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageLocalEdit)) { _ in scheduleOnChangeSync() }
        .onChange(of: router.deleteSelectedNonce) { _, _ in deleteSelectedFile() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await loadTree(); pruneDeletedContexts(); pruneTasks(); await runAutoSync() }
            updaterVM.checkInBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageGitSynced)) { _ in
            Task { await loadTree() }
        }
    }

    /// ⌘⌫ из меню: если дерево в фокусе — удалить выбранный в дереве файл/папку (с подтверждением);
    /// иначе — открытую заметку (тоже с подтверждением). Больше не «тупо удаляет».
    private func deleteSelectedFile() {
        if treeIsFocused {
            treeDeleteNonce += 1
            return
        }
        guard let url = router.selectedFile else { return }
        pendingFileDelete = FileNode(name: url.deletingPathExtension().lastPathComponent,
                                     url: url, isDirectory: false, depth: 0)
    }

    /// Убрать чаты/выбор для удалённых папок/файлов (после удаления через ИИ или вручную).
    private func pruneDeletedContexts() {
        let fm = FileManager.default
        for key in chatVMs.keys {
            let path: String?
            if key.hasPrefix("file:") { path = String(key.dropFirst(5)) }
            else if key.hasPrefix("folder:") { path = String(key.dropFirst(7)) }
            else { path = nil }
            if let path, !fm.fileExists(atPath: path) { chatVMs[key] = nil }
        }
        switch router.pendingChatContext {
        case let .folder(_, _, path) where !fm.fileExists(atPath: path),
             let .file(_, path) where !fm.fileExists(atPath: path):
            router.openChat(context: .vault)
        default: break
        }
        if let sel = router.selectedFile, !fm.fileExists(atPath: sel.path) { router.selectedFile = nil }
        Task {
            var deleted = false
            for s in await composition.chatStore.sessions() {
                guard let p = chatContextPath(s.context), !FileManager.default.fileExists(atPath: p) else { continue }
                await composition.chatStore.delete(id: s.id)
                deleted = true
            }
            if deleted { chatVMs.values.forEach { $0.refreshSessions() } }
        }
    }

    /// Путь файла/папки контекста чата (для чистки истории удалённых путей). nil для .vault/.selection.
    private func chatContextPath(_ ctx: ChatContext) -> String? {
        switch ctx {
        case let .file(_, p): p
        case let .folder(_, _, p): p
        default: nil
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            TitlebarView(
                crumbs: crumbSegments, hasNote: router.selectedFile != nil,
                vaultRoot: settings.resolveVaultURL(), fileURL: router.selectedFile,
                router: router, theme: theme,
                onCycleTheme: {
                    theme.cycle()
                    let name: String
                    switch theme.mode {
                    case .dark: name = s.theme.dark
                    case .light: name = s.theme.light
                    case .auto: name = s.theme.auto
                    }
                    toasts.success("🎨", "\(s.settings.theme): \(name)")
                }
            )
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
    }

    @ViewBuilder private var content: some View {
        ZStack {
            if router.view == .settings {
                SettingsView(
                    tab: settingsTabBinding,
                    models: composition.models,
                    git: composition.git,
                    updaterVM: updaterVM,
                    settings: settings,
                    onChangeVault: { openFolder() },
                    onToast: { icon, text, isError in
                        if isError { toasts.error(icon, text) } else { toasts.success(icon, text) }
                    }
                )
            } else {
                EditorView(
                    fileURL: router.selectedFile,
                    mode: router.editorMode,
                    variant: router.editorVariant,
                    vault: composition.vault,
                    markdown: composition.markdown,
                    ai: composition.ai,
                    spellcheck: settings.spellcheck,
                    onCreate: { createNote() },
                    onOpenFolder: { openFolder() },
                    onOpenNote: { url in router.selectedFile = url },
                    aiInvokeNonce: router.inlineAINonce,
                    vaultHasNotes: vaultHasNotes,
                    vaultRoot: settings.resolveVaultURL(),
                    onSelectionChanged: { settings.currentSelection = $0.isEmpty ? nil : $0 },
                    tasks: tasks
                )
                .id(settings.vaultPath)
            }
            if chatOpened, let vm = chatVMs[currentChatKey] {
                ChatView(
                    vm: vm,
                    markdown: composition.markdown,
                    onOpenNote: { url in router.selectedFile = url; router.go(.editor) },
                    onClearContext: {
                        router.openChat(context: .vault)
                        ensureChatVM(for: .vault)
                    },
                    onOpenSession: { session in
                        router.openChat(context: session.context)
                        ensureChatVM(for: session.context)
                        chatVMs[chatKey(for: session.context)]?.openSession(session)
                    },
                    vaultRoot: settings.resolveVaultURL()
                )
                .id(currentChatKey)
                .opacity(router.view == .chat ? 1 : 0)
                .allowsHitTesting(router.view == .chat)
            }
        }
        .onChange(of: router.view) { _, v in
            if v == .chat { chatOpened = true; ensureChatVM(); tasks.markRead(.chat(currentChatContext)) }
        }
        .onChange(of: currentChatKey) { _, _ in
            if chatOpened { ensureChatVM() }
            if router.view == .chat { tasks.markRead(.chat(currentChatContext)) }
            chatVMs[currentChatKey]?.historyOpen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageChatSessionDeleted)) { note in
            guard let ctx = note.object as? ChatContext else { return }
            let key = chatKey(for: ctx)
            if key != currentChatKey { chatVMs[key] = nil }
            chatVMs.values.forEach { $0.refreshSessions() }
            tasks.cancel(.chat(ctx))
            if case let .file(_, path) = ctx { tasks.cancel(.inline(path: path)) }
        }
        .onChange(of: router.chatPromptNonce) { _, _ in
            guard let prompt = router.pendingChatPrompt else { return }
            ensureChatVM()
            chatVMs[currentChatKey]?.sendPrompt(prompt)
        }
        .onChange(of: tasks.entries) { old, new in
            for (key, entry) in new where entry.phase == .readyUnread && old[key]?.phase != .readyUnread {
                if isCurrentTarget(entry.route) {
                    tasks.markRead(raw: key)
                } else {
                    toasts.show(Toast(icon: "✦", text: s.toast.aiReplied, subtitle: entry.label, kind: .success,
                                      action: ToastAction(label: s.app.open, route: entry.route)))
                }
            }
        }
    }

    /// Смотрит ли пользователь прямо сейчас на цель задачи (чтобы не показывать тост/свечение).
    private func isCurrentTarget(_ route: AITaskRoute) -> Bool {
        switch route {
        case let .openChat(ctx):
            return router.view == .chat && chatKey(for: currentChatContext) == chatKey(for: ctx)
        case let .openInline(path):
            return router.view == .editor && router.selectedFile?.path == path
        case .openUpdates, .restartUpdate:
            return false
        }
    }

    /// Открыть цель задачи из actionable-тоста.
    private func openTaskRoute(_ route: AITaskRoute) {
        switch route {
        case let .openChat(ctx):
            router.openChat(context: ctx)
        case let .openInline(path):
            router.selectedFile = URL(fileURLWithPath: path)
            router.go(.editor)
            tasks.markRead(.inline(path: path))
        case .openUpdates:
            router.settingsTab = .updates
            router.openSettings()
        case .restartUpdate:
            updaterVM.restart()
        }
    }

    /// Клик по индикатору ИИ-задачи на строке дерева → перейти в её чат/файл (по route из реестра).
    private func openNodeTask(_ node: FileNode) {
        let keys: [AITaskKey] = node.isDirectory
            ? [.chat(.folder(name: "", fileCount: 0, path: node.url.path))]
            : [.inline(path: node.url.path), .chat(.file(name: "", path: node.url.path))]
        if let entry = keys.compactMap({ tasks.entries[$0.raw] }).first {
            openTaskRoute(entry.route)
        }
        keys.forEach { tasks.markRead($0) }
    }

    /// Снять записи задач для несуществующих путей (удаление/смена хранилища).
    private func pruneTasks() {
        tasks.prune { raw in
            let parts = raw.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, ["file", "folder", "inline"].contains(String(parts[0])) else { return true }
            return FileManager.default.fileExists(atPath: String(parts[1]))
        }
    }

    /// Какой узел подсветить в сайдбаре: в режиме чата — папка/файл АКТИВНОГО контекста чата
    /// (а не последний открытый в редакторе файл); иначе — открытый файл. Чистая логика в CoreKit (тест).
    private var highlightedFileID: String? {
        sidebarHighlightID(view: router.view, chatContext: currentChatContext, editorFile: router.selectedFile?.path)
    }

    /// Ключ контекста чата (без nonce) — один постоянный VM на контекст.
    private var currentChatContext: ChatContext { router.pendingChatContext ?? .vault }
    private func chatKey(for context: ChatContext) -> String {
        switch context {
        case .vault: return "vault"
        case let .file(_, path): return "file:\(path)"
        case let .folder(_, _, path): return "folder:\(path)"
        case let .selection(name): return "selection:\(name)"
        }
    }
    private var currentChatKey: String { chatKey(for: currentChatContext) }

    /// Создать VM для контекста, если ещё нет (генерация прежних контекстов продолжается).
    private func ensureChatVM(for context: ChatContext) {
        let key = chatKey(for: context)
        if let existing = chatVMs[key], chatKey(for: existing.context) != key {
            chatVMs[key] = nil
        }
        guard chatVMs[key] == nil else { return }
        chatVMs[key] = ChatViewModel(
            context: context, ai: composition.ai, vault: composition.vault,
            speech: composition.speech, store: composition.chatStore,
            whisperURL: whisperURL, language: locale.language,
            vaultRoot: settings.resolveVaultURL(), tasks: tasks
        )
    }
    private func ensureChatVM() { ensureChatVM(for: currentChatContext) }

    // MARK: - Данные

    private func loadTree() async {
        guard let url = settings.resolveVaultURL() else { return }
        _ = url.startAccessingSecurityScopedResource()
        let root = try? await composition.vault.buildTree(at: url)
        tree = root?.children ?? []
        let exists = router.selectedFile.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if !exists { router.selectedFile = nil }
    }

    /// Включить живое наблюдение за текущим хранилищем — внешние правки сразу перестраивают дерево.
    private func startWatching() {
        guard let url = settings.resolveVaultURL() else { watcher.stop(); return }
        watcher.start(root: url) { Task { @MainActor in scheduleTreeReload() } }
    }

    private func scheduleTreeReload() {
        treeReloadTask?.cancel()
        treeReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await loadTree()
        }
    }

    // MARK: - Авто-синхронизация Git (Ит.44)

    /// Подключён ли git-remote (а не просто локальный .git).
    private var gitConnected: Bool { settings.gitRemote != nil }

    /// Перепривязать git к ТЕКУЩЕМУ vault: `settings.gitRemote` = фактический remote из `.git` нового
    /// хранилища (источник правды — сам репозиторий, привязка per-vault). Делает `gitConnected` и экран
    /// настроек корректными для нового vault, потом пере-оценивает таймер auto-sync. Звать на смене vault и старте.
    private func refreshGitBinding() {
        guard let url = settings.resolveVaultURL() else { settings.gitRemote = nil; startGitAutoSync(); return }
        Task {
            let remote = (await composition.git.info(at: url))?.remoteURL
            settings.gitRemote = (remote != nil && remote != "—" && !(remote ?? "").isEmpty) ? remote : nil
            startGitAutoSync()
        }
    }

    /// Выполнить авто-sync (pull тянет апдейты с других устройств + push локального). Тихо при успехе,
    /// тост только на конфликте. После — пост `.sageGitSynced` (дерево/открытый файл обновляются).
    @MainActor private func runAutoSync() async {
        guard settings.autoSync, settings.gitFrequency.isAutomatic, gitConnected,
              !gitSyncInFlight, let url = settings.resolveVaultURL() else { return }
        gitSyncInFlight = true
        /// Флаш ДО коммита: иначе sync закоммитит устаревшую (для свежей заметки — пустую) дисковую
        /// версию, а набранный текст останется только в памяти редактора. Затем — сигнал редактору
        /// отложить дебаунс-сейвы до конца sync (запись посреди rebase → abort откатил бы файл).
        NotificationCenter.default.post(name: .sageFlushAll, object: nil)
        NotificationCenter.default.post(name: .sageGitSyncBegan, object: nil)
        let message = Formatting.gitCommitMessage(action: s.git.commitAutoSync, date: Date())
        let outcome = await composition.git.sync(at: url, message: message)
        lastGitSyncAt = Date()
        gitSyncInFlight = false
        await loadTree()
        NotificationCenter.default.post(name: .sageGitSynced, object: nil)
        switch outcome {
        case .synced, .upToDate: break
        default: let t = gitSyncToast(outcome, s); toasts.error(t.icon, t.text)
        }
    }

    /// OTA: периодическая фоновая проверка обновлений (раз в сутки; сама проверка троттлится по lastUpdateCheck).
    private func startUpdatePoll() {
        updatePeriodicTask?.cancel()
        updatePeriodicTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(24 * 3600))
                if Task.isCancelled { break }
                updaterVM.checkInBackground()
            }
        }
    }

    /// OTA: фоновая фаза апдейтера → ненавязчивый тост. `.readyToInstall` (авто-режим) — «готово · Перезапустить»;
    /// `.available` (авто выкл) — «доступно · Открыть».
    private func handleUpdatePhase(_ phase: UpdaterPhase) {
        switch phase {
        case let .readyToInstall(r):
            toasts.show(Toast(icon: "✓", text: "\(s.settings.updateReadyTitle) · \(CoreKit.appName) \(r.version)",
                              kind: .success, action: ToastAction(label: s.settings.restartNow, route: .restartUpdate)))
        case let .available(r):
            toasts.show(Toast(icon: "↑", text: "\(s.settings.updateAvailableTitle) · \(r.version)",
                              kind: .info, action: ToastAction(label: s.settings.openAction, route: .openUpdates)))
        default: break
        }
    }

    /// Перезапустить периодический таймер по текущей частоте (вызывать при запуске и смене настроек/хранилища).
    private func startGitAutoSync() {
        gitPeriodicTask?.cancel()
        guard settings.autoSync, gitConnected,
              let interval = settings.gitFrequency.autoIntervalSeconds else { return }
        gitPeriodicTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await runAutoSync()
            }
        }
    }

    /// Дебаунс onChange-синка: правка → через ~2.5с push (если частота .onChange). Кулдаун 5с после
    /// любого sync гасит петлю (git-записи pull'а дёргают watcher, но не вызывают новый sync).
    private func scheduleOnChangeSync() {
        guard settings.autoSync, settings.gitFrequency.syncsOnChange, gitConnected, !gitSyncInFlight else { return }
        gitChangeDebounce?.cancel()
        gitChangeDebounce = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            guard Date().timeIntervalSince(lastGitSyncAt) > 5 else { return }
            await runAutoSync()
        }
    }

    /// Есть ли в хранилище хоть одна заметка (для выбора дефолтного стейта редактора).
    private var vaultHasNotes: Bool {
        tree.contains { !flattenFiles($0).isEmpty }
    }

    private func flattenFiles(_ node: FileNode) -> [URL] {
        if node.isDirectory { return node.children.flatMap { flattenFiles($0) } }
        return [node.url]
    }

    private func createNote() {
        guard canCreate(), let url = settings.resolveVaultURL() else { return }
        Task {
            if let created = try? await composition.vault.createNote(named: s.app.newNoteName, in: url) {
                await loadTree()
                router.selectedFile = created
                renamingID = created.path
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.setVault(url: url)
            toasts.success("📂", s.toast.folderOpened)
        }
    }

    // MARK: - Производные

    private var workspaceName: String {
        if settings.vaultPath.isEmpty { return "Sage" }
        return URL(fileURLWithPath: settings.vaultPath).lastPathComponent
    }

    /// Сегменты хлебных крошек: workspace + папки/подпапки + имя файла (без .md).
    private var crumbSegments: [String] {
        guard let file = router.selectedFile else { return [workspaceName, s.nav.editor] }
        let fileName = file.deletingPathExtension().lastPathComponent
        var folders: [String] = []
        if let root = settings.resolveVaultURL() {
            let rootComps = root.standardizedFileURL.pathComponents
            let parentComps = file.standardizedFileURL.deletingLastPathComponent().pathComponents
            if parentComps.count >= rootComps.count, Array(parentComps.prefix(rootComps.count)) == rootComps {
                folders = Array(parentComps.dropFirst(rootComps.count))
            }
        }
        return [workspaceName] + folders + [fileName]
    }

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var settingsTabBinding: Binding<SettingsTab> {
        Binding(get: { router.settingsTab }, set: { router.settingsTab = $0 })
    }

    private func createFolderRoot() {
        guard canCreate(), let url = settings.resolveVaultURL() else { return }
        Task {
            if let created = try? await composition.vault.createFolder(named: s.app.newFolder, in: url) {
                await loadTree()
                renamingID = created.path
            }
        }
    }

    private func createNoteIn(_ node: FileNode) {
        guard canCreate() else { return }
        Task {
            if let created = try? await composition.vault.createNote(named: s.app.newNoteName, content: "", in: node.url) {
                expanded.insert(node.id)
                await loadTree()
                router.selectedFile = created
                renamingID = created.path
            }
        }
    }

    private func createFolderIn(_ node: FileNode) {
        guard canCreate() else { return }
        Task {
            if let created = try? await composition.vault.createFolder(named: s.app.newFolder, in: node.url) {
                expanded.insert(node.id)
                await loadTree()
                renamingID = created.path
            }
        }
    }

    private func renameItem(_ node: FileNode, to newName: String) {
        Task {
            if let newURL = try? await composition.vault.rename(at: node.url, to: newName) {
                if router.selectedFile == node.url { router.selectedFile = newURL }
                await loadTree()
            }
        }
    }

    private func deleteItem(_ node: FileNode) {
        if node.isDirectory {
            pendingFolderDelete = node
        } else {
            pendingFileDelete = node
        }
    }

    /// Удаление файла/папки → подчистить ВСЕ связанные с этим путём чаты: сброс открытого чата в vault,
    /// убийство keep-alive VM (+ stop генерации), удаление осиротевших сессий истории из стора.
    /// Покрывает корнеры: открыт в редакторе / контекст текущего чата / контекст фонового VM / вложенные файлы папки.
    private func cleanupContexts(forDeletedPath path: String) {
        func ctxPath(_ ctx: ChatContext) -> String? {
            switch ctx { case let .file(_, p): return p; case let .folder(_, _, p): return p; default: return nil }
        }
        func affected(_ p: String?) -> Bool { guard let p else { return false }; return p == path || p.hasPrefix(path + "/") }
        if router.view == .chat, affected(ctxPath(currentChatContext)) {
            router.openChat(context: .vault); ensureChatVM(for: .vault)
        }
        for (key, vm) in chatVMs where affected(ctxPath(vm.context)) {
            vm.stop(); chatVMs[key] = nil
        }
        Task {
            for s in await composition.chatStore.sessions() where affected(ctxPath(s.context)) {
                await composition.chatStore.delete(id: s.id)
            }
            chatVMs[currentChatKey]?.refreshSessions()
        }
    }

    private func performDelete(_ node: FileNode) {
        cleanupContexts(forDeletedPath: node.url.path)
        let affectsOpen = router.selectedFile.map { $0 == node.url || $0.path.hasPrefix(node.url.path + "/") } ?? false
        if affectsOpen { router.selectedFile = nil }
        Task {
            if affectsOpen { try? await Task.sleep(nanoseconds: 130_000_000) }
            try? await composition.vault.deleteNote(at: node.url)
            try? await Task.sleep(nanoseconds: 250_000_000)
            await loadTree()
            toasts.success("🗑", s.chat.deleted)
        }
    }

    private var actions: SidebarActions {
        SidebarActions(
            onWorkspace: { openFolder() },
            onSearch: { router.searchOpen = true },
            onEditor: { router.go(.editor) },
            onChat: { router.openChat(context: .vault); ensureChatVM(for: .vault) },
            onSettings: { router.openSettings() },
            onNewFile: { createNote() },
            onNewFolder: { createFolderRoot() },
            onSelect: { node in
                router.selectedFile = node.url
                router.go(.editor)
                if !node.isDirectory { tasks.markRead(.inline(path: node.url.path)) }
            },
            onAsk: { node in
                let ctx: ChatContext = node.isDirectory
                    ? .folder(name: node.name, fileCount: flattenFiles(node).count, path: node.url.path)
                    : .file(name: node.name, path: node.url.path)
                router.openChat(context: ctx)
            },
            onCreateNote: { createNoteIn($0) },
            onCreateFolder: { createFolderIn($0) },
            onDelete: { deleteItem($0) },
            onRename: { renameItem($0, to: $1) },
            onDeleteMany: { paths in deleteMany(paths) },
            onOpenTask: { node in openNodeTask(node) },
            onCursor: { node in treeCursorNode = node },
            onTreeFocus: { focused in treeIsFocused = focused },
            onSetSort: { settings.sidebarSort = $0 }
        )
    }

    private func deleteMany(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        for p in paths { cleanupContexts(forDeletedPath: p) }
        let affectsOpen = router.selectedFile.map { sel in urls.contains { sel == $0 || sel.path.hasPrefix($0.path + "/") } } ?? false
        if affectsOpen { router.selectedFile = nil }
        Task {
            if affectsOpen { try? await Task.sleep(nanoseconds: 130_000_000) }
            for url in urls { try? await composition.vault.deleteNote(at: url) }
            try? await Task.sleep(nanoseconds: 250_000_000)
            await loadTree()
            toasts.success("🗑", s.chat.deleted)
        }
    }
}
