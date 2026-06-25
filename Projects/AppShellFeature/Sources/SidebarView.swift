import AppKit
import CoreKit
import DesignSystem
import Localization
import SwiftUI

/// Колбэки боковой панели (инжектируются композицией App).
public struct SidebarActions {
    public var onWorkspace: () -> Void
    public var onSearch: () -> Void
    public var onEditor: () -> Void
    public var onChat: () -> Void
    public var onSettings: () -> Void
    public var onNewFile: () -> Void
    public var onNewFolder: () -> Void
    public var onSelect: (FileNode) -> Void
    public var onAsk: (FileNode) -> Void
    public var onCreateNote: (FileNode) -> Void
    public var onCreateFolder: (FileNode) -> Void
    public var onDelete: (FileNode) -> Void
    public var onRename: (FileNode, String) -> Void
    public var onDeleteMany: ([String]) -> Void
    /// Клик по индикатору фоновой ИИ-задачи на строке → перейти в её чат/файл.
    public var onOpenTask: (FileNode) -> Void = { _ in }
    /// Текущий курсор дерева (для ⌘⌫ из меню, когда дерево в фокусе).
    public var onCursor: (FileNode?) -> Void = { _ in }
    /// Фокус дерева получен/потерян.
    public var onTreeFocus: (Bool) -> Void = { _ in }
    /// Смена режима сортировки (персистится в SettingsStore композицией App).
    public var onSetSort: (SidebarSort) -> Void = { _ in }

    public init(
        onWorkspace: @escaping () -> Void, onSearch: @escaping () -> Void,
        onEditor: @escaping () -> Void, onChat: @escaping () -> Void,
        onSettings: @escaping () -> Void, onNewFile: @escaping () -> Void,
        onNewFolder: @escaping () -> Void, onSelect: @escaping (FileNode) -> Void,
        onAsk: @escaping (FileNode) -> Void, onCreateNote: @escaping (FileNode) -> Void,
        onCreateFolder: @escaping (FileNode) -> Void, onDelete: @escaping (FileNode) -> Void,
        onRename: @escaping (FileNode, String) -> Void,
        onDeleteMany: @escaping ([String]) -> Void = { _ in },
        onOpenTask: @escaping (FileNode) -> Void = { _ in },
        onCursor: @escaping (FileNode?) -> Void = { _ in },
        onTreeFocus: @escaping (Bool) -> Void = { _ in },
        onSetSort: @escaping (SidebarSort) -> Void = { _ in }
    ) {
        self.onWorkspace = onWorkspace; self.onSearch = onSearch
        self.onEditor = onEditor; self.onChat = onChat
        self.onSettings = onSettings; self.onNewFile = onNewFile
        self.onNewFolder = onNewFolder; self.onSelect = onSelect
        self.onAsk = onAsk; self.onCreateNote = onCreateNote
        self.onCreateFolder = onCreateFolder; self.onDelete = onDelete
        self.onRename = onRename; self.onDeleteMany = onDeleteMany
        self.onOpenTask = onOpenTask
        self.onCursor = onCursor; self.onTreeFocus = onTreeFocus
        self.onSetSort = onSetSort
    }
}

public struct SidebarView: View {
    private let workspaceName: String
    private let vaultPath: String
    private let tree: [FileNode]
    @Binding private var expanded: Set<String>
    private let selectedFileID: String?
    private let activeModelName: String
    private let sort: SidebarSort
    private let deleteNonce: Int
    private let actions: SidebarActions

    @Environment(\.palette) private var palette
    @Environment(AppRouter.self) private var router
    @Environment(LocaleManager.self) private var locale
    @Environment(AITaskRegistry.self) private var tasks
    @Binding private var renamingID: String?
    @State private var multiSel: Set<String> = []
    @State private var cursorID: String?
    @FocusState private var treeFocused: Bool
    @State private var isFullscreen = false
    @State private var flat: [FileNode] = []

    public init(
        workspaceName: String, vaultPath: String, tree: [FileNode],
        expanded: Binding<Set<String>>, selectedFileID: String?,
        activeModelName: String, sort: SidebarSort = .name,
        renamingID: Binding<String?>, deleteNonce: Int = 0, actions: SidebarActions
    ) {
        self.workspaceName = workspaceName
        self.vaultPath = vaultPath
        self.tree = tree
        _expanded = expanded
        self.selectedFileID = selectedFileID
        self.activeModelName = activeModelName
        self.sort = sort
        self.deleteNonce = deleteNonce
        _renamingID = renamingID
        self.actions = actions
    }

    private var s: Strings { locale.strings }

    public var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: isFullscreen ? 6 : 28)
            workspaceSwitcher
            navSection
            Divider().overlay(palette.bd).padding(.horizontal, Spacing.sm).padding(.vertical, 6)
            fileTree
            footer
        }
        .frame(maxWidth: .infinity)
        .background(palette.bg1)
        .overlay(alignment: .trailing) { Rectangle().fill(palette.bd).frame(width: 1) }
        .onAppear { isFullscreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in isFullscreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in isFullscreen = false }
    }

    private var workspaceSwitcher: some View {
        Button(action: actions.onWorkspace) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#1C2A22"), Color(hex: "#11151A")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .overlay(SparkLogo(size: 13, color: palette.ac))
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspaceName).sageType(.uiMedium).foregroundStyle(palette.tx).lineLimit(1)
                    Text(vaultPath).font(.sage(11)).foregroundStyle(palette.tx3).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(palette.tx3)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.bgh)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var navSection: some View {
        VStack(spacing: 2) {
            navRow(icon: "magnifyingglass", title: s.nav.search, trailing: .shortcut("⌘F"), action: actions.onSearch)
            navRow(icon: "bubble.left", title: s.nav.chat,
                   trailing: .status(nodeChatPhase), active: router.view == .chat && chatIsVaultLevel, action: actions.onChat)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    /// Чат сейчас на уровне хранилища (а не конкретной папки/файла)?
    private var chatIsVaultLevel: Bool {
        switch router.pendingChatContext ?? .vault {
        case .file, .folder: return false
        case .vault, .selection: return true
        }
    }

    /// Фаза задачи общего чата (для индикатора в нав-строке «Чат с Sage»).
    private var nodeChatPhase: AITaskPhase? { tasks.phase(.chat(.vault)) }

    private enum Trailing { case none, shortcut(String), dot, status(AITaskPhase?) }

    private func navRow(icon: String, title: String, trailing: Trailing = .none, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 16)
                Text(title).sageType(.ui)
                Spacer(minLength: 0)
                switch trailing {
                case .none: EmptyView()
                case let .shortcut(key):
                    Text(key).font(.sage(10.5)).foregroundStyle(palette.tx3)
                        .padding(.horizontal, 5).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.bd, lineWidth: 1))
                case .dot: StatusDot(size: 6)
                case let .status(phase):
                    if let phase { AITaskBadge(phase: phase) } else if active { StatusDot(size: 6) }
                }
            }
            .foregroundStyle(active ? palette.tx : palette.tx2)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(active ? palette.bgh : .clear, in: RoundedRectangle(cornerRadius: Radius.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.bgh)
    }

    private var fileTree: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                treeHeader
                ScrollView {
                    treeContent
                }
                .scrollIndicators(.hidden)
                .focusable()
                .focusEffectDisabled()
                .focused($treeFocused)
                .onMoveCommand { moveCursor($0) }
            .onKeyPress(.return) { onReturnKey() ? .handled : .ignored }
            .onKeyPress(phases: .down) { press in
                guard press.key == .delete || press.key == .deleteForward else { return .ignored }
                return onDeleteKey() ? .handled : .ignored
            }
            .onChange(of: treeFocused) { _, f in actions.onTreeFocus(f) }
            .onChange(of: cursorID) { _, id in
                actions.onCursor(flatNodes.first { $0.id == id })
                if let id { withAnimation(SageMotion.quick) { proxy.scrollTo(id, anchor: .center) } }
            }
            .onChange(of: selectedFileID) { _, id in
                guard let id else { return }
                ensureVisible(id: id)
                cursorID = id
            }
            .onChange(of: renamingID) { _, id in
                if let id { withAnimation(SageMotion.quick) { proxy.scrollTo(id, anchor: .center) } }
            }
            .onChange(of: deleteNonce) { _, _ in _ = onDeleteKey() }
            .onAppear { flat = computeFlat() }
            .onChange(of: tree) { _, _ in flat = computeFlat() }
            .onChange(of: sort) { _, _ in flat = computeFlat() }
            .onChange(of: expanded) { _, _ in flat = computeFlat() }
            }
        }
    }

    /// Шапка «ФАЙЛЫ» + тулбар (сортировка/новый) — закреплена над деревом (вне ScrollView).
    private var treeHeader: some View {
        HStack(spacing: 4) {
            Text(s.app.files.uppercased()).sageType(.caption).foregroundStyle(palette.tx3)
            Spacer()
            Menu {
                Button { actions.onSetSort(.name) } label: {
                    Label(s.app.sortByName, systemImage: sort == .name ? "checkmark" : "")
                }
                Button { actions.onSetSort(.modified) } label: {
                    Label(s.app.sortByModified, systemImage: sort == .modified ? "checkmark" : "")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.tx3).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(palette.tx3)
            .hoverHighlight(palette.bgh, radius: Radius.xs)
            .help(s.app.sortBy)
            Menu {
                Button { actions.onNewFile() } label: { Label(s.app.newNote, systemImage: "doc.badge.plus") }
                Button { actions.onNewFolder() } label: { Label(s.app.newFolder, systemImage: "folder.badge.plus") }
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.tx3).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(palette.tx3)
            .hoverHighlight(palette.bgh, radius: Radius.xs)
            .help(s.app.newNote)
        }
        .padding(.horizontal, 14).padding(.bottom, 6).padding(.top, 8)
    }

    /// Enter по дереву: на папке — раскрыть/свернуть (анимировано), на файле — открыть.
    private func onReturnKey() -> Bool {
        if renamingID != nil { return false }
        guard let id = cursorID, let node = flatNodes.first(where: { $0.id == id }) else { return false }
        if node.isDirectory {
            withAnimation(SageMotion.smooth) {
                if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
            }
        } else {
            actions.onSelect(node)
        }
        return true
    }

    /// Delete по дереву: удалить мультивыбор, иначе — узел под курсором.
    private func onDeleteKey() -> Bool {
        if renamingID != nil { return false }
        if !multiSel.isEmpty {
            let ids = Array(multiSel); multiSel.removeAll(); actions.onDeleteMany(ids); return true
        }
        if let id = cursorID, let node = flatNodes.first(where: { $0.id == id }) {
            actions.onDelete(node); return true
        }
        return false
    }

    private var treeContent: some View {
            LazyVStack(spacing: 1) {
                ForEach(flatNodes) { node in
                    FileRow(
                        node: node,
                        selected: SidebarView.rowSelected(id: node.id, selectedFileID: selectedFileID,
                                                          cursorID: cursorID, treeFocused: treeFocused, multiSel: multiSel),
                        expanded: expanded.contains(node.id),
                        renamingID: $renamingID,
                        strings: s,
                        selectedCount: multiSel.count,
                        onTap: { handleTap(node) },
                        onAsk: { actions.onAsk(node) },
                        onCreateNote: { actions.onCreateNote(node) },
                        onCreateFolder: { actions.onCreateFolder(node) },
                        onDelete: { actions.onDelete(node) },
                        onDeleteSelected: { let ids = Array(multiSel); multiSel.removeAll(); actions.onDeleteMany(ids) },
                        onOpenTask: { actions.onOpenTask(node) },
                        onRename: { actions.onRename(node, $0) }
                    )
                    .id(node.id)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .animation(SageMotion.smooth, value: expanded)
    }

    /// Подсвечена ли строка — РОВНО ОДНА активная (без двойной подсветки).
    /// Мультивыбор — всегда. При фокусе дерева активен курсор (клавиши/клик), иначе — открытый файл.
    /// Так навигация стрелками на папку НЕ оставляет вторую подсветку на ранее открытом файле.
    static func rowSelected(id: String, selectedFileID: String?, cursorID: String?,
                            treeFocused: Bool, multiSel: Set<String>) -> Bool {
        if multiSel.contains(id) { return true }
        if treeFocused, let cursorID { return id == cursorID }
        return id == selectedFileID
    }

    /// Плоское дерево (кэш): пересчитывается ТОЛЬКО при смене tree/sort/expanded, а не на каждое
    /// чтение — иначе O(n·log n) localized-сортировка гонялась на каждый кадр body и каждое ↑/↓.
    private var flatNodes: [FileNode] { flat }

    /// Раскрыть ВСЕ папки-предки узла `id` (чтобы он попал в flat → хайлайт/скролл попадают по нему).
    /// Для узла верхнего уровня — no-op. Мутация `expanded` триггерит пересчёт flat (onChange выше).
    private func ensureVisible(id: String) {
        for ancestor in sidebarAncestorFolderIDs(of: id, in: tree) { expanded.insert(ancestor) }
    }

    /// Рекурсивный flatten с учётом раскрытых папок и сортировки (папки→файлы, имя/дата).
    private func computeFlat() -> [FileNode] {
        func flatten(_ node: FileNode) -> [FileNode] {
            var rows = [node]
            if node.isDirectory, expanded.contains(node.id) {
                for child in node.sortedChildren(by: sort) { rows += flatten(child) }
            }
            return rows
        }
        return sortedFileNodes(tree, by: sort).flatMap(flatten)
    }

    private func handleTap(_ node: FileNode) {
        treeFocused = true
        let anchor = cursorID ?? selectedFileID
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        cursorID = node.id
        if cmd {
            if multiSel.contains(node.id) { multiSel.remove(node.id) } else { multiSel.insert(node.id) }
            return
        }
        if shift {
            if let from = anchor,
               let a = flatNodes.firstIndex(where: { $0.id == from }),
               let b = flatNodes.firstIndex(where: { $0.id == node.id }) {
                for i in min(a, b) ... max(a, b) { multiSel.insert(flatNodes[i].id) }
            } else {
                multiSel.insert(node.id)
            }
            return
        }
        multiSel.removeAll()
        if node.isDirectory {
            withAnimation(SageMotion.smooth) {
                if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
            }
        } else {
            actions.onSelect(node)
        }
    }

    /// Клавиатурная навигация ↑/↓ по плоскому дереву; ⇧ расширяет мультивыбор.
    private func moveCursor(_ dir: MoveCommandDirection) {
        let nodes = flatNodes
        guard !nodes.isEmpty else { return }
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let curIdx = nodes.firstIndex { $0.id == cursorID }
            ?? nodes.firstIndex { $0.id == selectedFileID }
            ?? -1
        var next = curIdx
        switch dir {
        case .down: next = curIdx < 0 ? 0 : min(nodes.count - 1, curIdx + 1)
        case .up: next = curIdx < 0 ? 0 : max(0, curIdx - 1)
        default: return
        }
        guard next >= 0, next < nodes.count else { return }
        let node = nodes[next]
        cursorID = node.id
        if shift {
            if curIdx >= 0 { multiSel.insert(nodes[curIdx].id) }
            multiSel.insert(node.id)
        } else {
            multiSel.removeAll()
            if !node.isDirectory { actions.onSelect(node) }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            StatusDot(size: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(activeModelName).font(.sage(12, .medium)).foregroundStyle(palette.tx).lineLimit(1)
                Text(s.app.localRunning).font(.sage(10.5)).foregroundStyle(palette.tx3)
            }
            Spacer(minLength: 0)
            Button(action: actions.onSettings) {
                GearIcon(size: 14, color: palette.tx3).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(palette.bgh)
            .help(s.settings.title)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(palette.bd).frame(height: 1) }
    }
}

/// Индикатор фоновой задачи ИИ: спиннер (работает) / пульс-искра или пилл «✦ готово» (готово) / ошибка.
private struct AITaskBadge: View {
    let phase: AITaskPhase
    var isFolder: Bool = false
    var readyLabel: String = ""
    @Environment(\.palette) private var palette

    var body: some View {
        switch phase {
        case .running:
            SageSpinner(size: 11)
        case .readyUnread:
            if isFolder {
                HStack(spacing: 4) {
                    SparkMark(size: 8, color: palette.ac)
                    Text(readyLabel).font(.sage(10, .semibold)).foregroundStyle(palette.ac).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(palette.acs, in: Capsule())
                .fixedSize()
            } else {
                GlowRing(size: 13, sparkSize: 8)
            }
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(palette.error)
        }
    }
}

/// Строка файла/папки: hover-кнопки ✦/⋯, контекстное меню, инлайн-переименование.
private struct FileRow: View {
    let node: FileNode
    let selected: Bool
    let expanded: Bool
    @Binding var renamingID: String?
    let strings: Strings
    var selectedCount: Int = 0
    let onTap: () -> Void
    let onAsk: () -> Void
    let onCreateNote: () -> Void
    let onCreateFolder: () -> Void
    let onDelete: () -> Void
    var onDeleteSelected: () -> Void = {}
    var onOpenTask: () -> Void = {}
    let onRename: (String) -> Void

    @Environment(\.palette) private var palette
    @Environment(AITaskRegistry.self) private var tasks
    @State private var hovering = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private var isRenaming: Bool { renamingID == node.id }

    /// Имя для показа: у заметок скрываем расширение `.md`.
    private var displayName: String {
        node.isDirectory ? node.name : node.name.withoutMDExtension
    }

    private var indent: CGFloat { CGFloat(min(node.depth, 6)) * 16 + 8 }
    private var rowVPad: CGFloat { node.isDirectory ? 6 : 5 }
    /// Детерминированная высота КОНТЕНТА строки = высота иконки (16 папка / 15 файл), как в браузере
    /// (там высоту строки держит иконка, а не line-height текста). Фиксируем её, чтобы убрать «воздух»
    /// от SwiftUI Text leading и получить ту же плотность, что в макете. При rename — nil (редактор
    /// шире/выше, ему нужна своя высота, иначе обрежется бордер/каретка).
    private var contentH: CGFloat? { isRenaming ? nil : (node.isDirectory ? 16 : 15) }
    private var iconColor: Color {
        (selected || fileReady) ? palette.ac : (node.isDirectory ? palette.tx2 : palette.tx3)
    }

    /// Фаза фоновой задачи ИИ для этого узла.
    private var aiPhase: AITaskPhase? { nodeAIPhase(node, tasks) }
    /// Файл с готовым непрочитанным ответом → строка зеленится (по макету Секция 05, состояние 3).
    private var fileReady: Bool { !node.isDirectory && aiPhase == .readyUnread }
    /// Показывать ли ✦-кнопку наведения (и прятать статус-счётчик/пилл, чтобы не накладывались).
    private var showHoverButtons: Bool {
        sidebarShowsHoverAsk(hovering: hovering, isRenaming: isRenaming, hasTask: aiPhase != nil)
    }
    private var rowBg: Color {
        if fileReady { return palette.ac.opacity(0.06) }
        return selected ? palette.bgh : .clear
    }

    /// Линейная иконка узла: папка (открытая/закрытая) или документ; активная — акцентом.
    @ViewBuilder private var rowIcon: some View {
        if node.isDirectory {
            SageGlyphIcon(expanded ? .folderOpen : .folderClosed, size: 16, color: iconColor)
        } else {
            SageGlyphIcon(.fileDoc, size: 15, color: iconColor)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if node.isDirectory {
                SageGlyphIcon(.chevron, size: 11, color: palette.tx3)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            } else {
                Color.clear.frame(width: 11, height: 11)
            }
            rowIcon.frame(width: 16)
            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.sage(12.5))
                    .focused($renameFocused)
                    .padding(.vertical, 2).padding(.horizontal, 6)
                    .background(palette.inp, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.ac, lineWidth: 1))
                    .onSubmit(commitRename)
                    .onExitCommand { renamingID = nil }
                    .onAppear { renameText = node.name; renameFocused = true }
                    .onChange(of: renameFocused) { _, focused in if !focused, isRenaming { commitRename() } }
            } else {
                Text(displayName)
                    .font(.sage(12.5, fileReady ? .semibold : (selected ? .medium : .regular)))
                    .foregroundStyle((selected || fileReady) ? palette.tx : palette.tx2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                smallStatus
                    .frame(width: hasTrailingContent ? statusSlot : 0, height: hasTrailingContent ? statusSlotH : nil, alignment: .trailing)
                    .opacity(showHoverButtons ? 0 : 1)
                    .allowsHitTesting(!showHoverButtons)
            }
        }
        .frame(height: contentH)
        .padding(.leading, indent)
        .padding(.trailing, 10)
        .padding(.vertical, rowVPad)
        .background(rowBg, in: RoundedRectangle(cornerRadius: Radius.xs))
        .overlay(alignment: .leading) { treeGuides }
        .overlay(alignment: .leading) { accentBar }
        .overlay(alignment: .trailing) {
            if showHoverButtons {
                hoverButtons.padding(.trailing, 8)
                    .transition(.scale(scale: 0.4, anchor: .trailing).combined(with: .opacity)
                        .combined(with: .move(edge: .trailing)))
            } else if node.isDirectory, aiPhase == .readyUnread {
                Button(action: onOpenTask) {
                    AITaskBadge(phase: .readyUnread, isFolder: true, readyLabel: strings.app.ready)
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(strings.app.open)
                .hoverHighlight(palette.bgh, radius: Radius.sm)
                .padding(.trailing, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming { onTap() } }
        .onHover { h in withAnimation(SageMotion.pop) { hovering = h } }
        .contextMenu { rowMenuItems }
    }

    /// Направляющие дерева: вертикальные линии на каждом уровне вложенности.
    @ViewBuilder private var treeGuides: some View {
        if node.depth >= 1 {
            ZStack(alignment: .leading) {
                ForEach(1 ... min(node.depth, 6), id: \.self) { level in
                    Rectangle().fill(palette.bd).frame(width: 1)
                        .offset(x: CGFloat(level - 1) * 16 + 15)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Левый акцентный бар — у активной строки И у файла с готовым ответом (Секция 05, состояние 3).
    @ViewBuilder private var accentBar: some View {
        if selected || fileReady {
            RoundedRectangle(cornerRadius: 1).fill(palette.ac)
                .frame(width: 2).padding(.vertical, rowVPad)
                .allowsHitTesting(false)
        }
    }

    /// Хвост строки ФИКСИРОВАННОЙ ширины (ZStack: оба слоя всегда в layout → ширина не меняется на hover,
    /// нет дёрганья). running-спиннер виден всегда; hover-кнопки и индикатор кросс-фейдятся opacity.
    @ViewBuilder private var hoverButtons: some View {
        Button(action: onAsk) {
            SparkMark(size: 14, color: palette.ac).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverHighlight(palette.bgh, radius: Radius.xs)
    }

    /// Есть ли что показать в трейлинге (задача ИЛИ счётчик папки) → резервировать фикс-слот.
    private var hasTrailingContent: Bool {
        sidebarReservesStatusSlot(hasTask: aiPhase != nil, isDirectory: node.isDirectory, mdCount: node.mdCount)
    }
    /// Ширина/высота фикс-слота статуса в потоке. Фикс-ВЫСОТА → count/спиннер/готово занимают одинаковый
    /// footprint → ни фаза ИИ, ни hover не меняют высоту строки. Пилл «готово» — НЕ тут (overlay).
    private let statusSlot: CGFloat = 26
    private let statusSlotH: CGFloat = 18

    /// МЕЛКИЙ статус в потоке (фикс-слот): спиннер / GlowRing файла / счётчик. Папка-готово → пусто (пилл в overlay).
    @ViewBuilder private var smallStatus: some View {
        if let phase = aiPhase {
            if node.isDirectory, phase == .readyUnread {
                Color.clear
            } else {
                Button(action: onOpenTask) {
                    AITaskBadge(phase: phase, isFolder: false, readyLabel: strings.app.ready)
                        .frame(width: 22, height: statusSlotH).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(strings.app.open)
                .hoverHighlight(palette.bgh, radius: Radius.xs)
            }
        } else if node.isDirectory, node.mdCount > 0 {
            Text("\(node.mdCount)").font(.sage(11)).foregroundStyle(palette.tx3)
        }
    }

    @ViewBuilder private var rowMenuItems: some View {
        if selectedCount > 1 {
            Button(role: .destructive) { onDeleteSelected() } label: {
                Label("\(strings.common.delete) (\(selectedCount))", systemImage: "trash")
            }
            Divider()
        }
        if node.isDirectory {
            Button { onCreateNote() } label: { Label(strings.app.newNote, systemImage: "doc.badge.plus") }
            Button { onCreateFolder() } label: { Label(strings.app.newFolder, systemImage: "folder.badge.plus") }
            Divider()
            Button { startRename() } label: { Label(strings.app.rename, systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label(strings.app.deleteFolder, systemImage: "trash") }
        } else {
            Button { startRename() } label: { Label(strings.app.rename, systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label(strings.common.delete, systemImage: "trash") }
        }
    }

    private func startRename() {
        renameText = node.name
        renamingID = node.id
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        renamingID = nil
        if !trimmed.isEmpty, trimmed != node.name { onRename(trimmed) }
    }
}
