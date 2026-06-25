import CoreKit
import DesignSystem
import Localization
import SwiftUI

public struct ChatView: View {
    private let vm: ChatViewModel
    @FocusState private var inputFocused: Bool
    @FocusState private var histFocused: Bool
    @State private var histCursor = 0
    private let markdown: MarkdownRendering
    private let onOpenNote: (URL) -> Void
    private let onClearContext: () -> Void
    /// Открыть сессию из истории — через App (роутер), чтобы pendingChatContext == vm.context (нет divergence).
    private let onOpenSession: (ChatSession) -> Void
    private let vaultRoot: URL?

    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale

    /// Стабильный ключ темы — `.id(themeKey)` пересоздаёт NSTextField (кэширует textColor) при смене темы.
    private var themeKey: String { palette.key }

    public init(
        vm: ChatViewModel, markdown: MarkdownRendering,
        onOpenNote: @escaping (URL) -> Void = { _ in },
        onClearContext: @escaping () -> Void = {},
        onOpenSession: @escaping (ChatSession) -> Void = { _ in },
        vaultRoot: URL? = nil
    ) {
        self.vm = vm
        self.markdown = markdown
        self.onOpenNote = onOpenNote
        self.onClearContext = onClearContext
        self.onOpenSession = onOpenSession
        self.vaultRoot = vaultRoot
    }

    private var s: Strings { locale.strings }

    /// Идёт голос (Слушаю/доступ/Распознаю) — orb-оверлей поверх чата, хедер/поле ввода скрыты, Esc/Enter на оверлее.
    /// Распознавание тоже под оверлеем: при ✓/Enter инпут не мелькает, текст уходит в чат, потом — пустой инпут.
    private var voiceOverlayActive: Bool { voiceShowsOrbOverlay(vm.voice) }

    /// Заголовок оверлея под текущую фазу.
    private var voiceOverlayTitle: String {
        switch vm.voice {
        case .permission: s.chat.perm
        case .transcribing: s.chat.transcribing
        default: s.chat.voiceTitle
        }
    }

    /// Высота области чата — дистанция «шторы» истории (закрыта = сдвиг на -chatAreaH). Дефолт большой →
    /// панель спрятана до первого замера (без вспышки).
    @State private var chatAreaH: CGFloat = 2000

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        messagesList
                        composer
                    }
                    historyPanel.sageElevation(palette)
                        .offset(y: vm.historyOpen ? 0 : -max(chatAreaH, 1))
                        .allowsHitTesting(vm.historyOpen)
                }
                .background(GeometryReader { g in Color.clear.preference(key: ChatAreaHeightKey.self, value: g.size.height) })
                .onPreferenceChange(ChatAreaHeightKey.self) { chatAreaH = $0 }
                .clipped()
            }
            if voiceOverlayActive {
                VoiceOrbOverlay(
                    phase: vm.voice, levels: vm.waveLevels, recordingStart: vm.recordingStart,
                    title: voiceOverlayTitle,
                    hint: s.chat.voiceHint, cancelLabel: s.chat.voiceCancel, confirmLabel: s.chat.voiceConfirm,
                    onCancel: { vm.cancelVoice() }, onConfirm: { vm.confirmVoice() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: voiceOverlayActive)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: vm.historyOpen)
        .background(palette.bg)
        .onChange(of: vm.historyOpen) { _, open in
            if open {
                vm.refreshSessions()
                histCursor = 0; DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { histFocused = true }
            }
            else { inputFocused = true }
        }
        .onExitCommand { if vm.historyOpen { vm.toggleHistory() } else { inputFocused = false } }
        .environment(\.openURL, OpenURLAction(handler: handleChatLink))
        .task {
            await vm.bootstrap()
            inputFocused = true
        }
    }

    /// Ссылки из ответов ИИ: внутренние `.md` открываем в Sage, http — в браузере.
    private func handleChatLink(_ url: URL) -> OpenURLAction.Result {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "mailto" {
            return .systemAction
        }
        let rel = url.relativeString.normalizedLinkTarget
        if let resolved = resolveNote(rel) { onOpenNote(resolved); return .handled }
        return .discarded
    }

    private func resolveNote(_ rel: String) -> URL? {
        guard let root = vaultRoot else { return nil }
        let direct = URL(fileURLWithPath: rel, relativeTo: root).standardizedFileURL
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let withMd = direct.pathExtension.isEmpty ? direct.appendingPathExtension("md") : direct
        if FileManager.default.fileExists(atPath: withMd.path) { return withMd }
        let target = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        if !target.isEmpty, let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension == "md" {
                if u.deletingPathExtension().lastPathComponent.lowercased() == target { return u }
            }
        }
        return nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            SparkMark(size: 17, color: palette.ac)
            Text(s.chat.title).font(.sage(14, .semibold)).foregroundStyle(palette.tx)
            Spacer()
            contextChip
            Button { vm.toggleHistory() } label: {
                HStack(spacing: 6) {
                    SageGlyphIcon(.clock, size: 13, color: vm.historyOpen ? palette.ac : palette.tx2)
                    Text(s.chat.history).font(.sage(12)).foregroundStyle(vm.historyOpen ? palette.ac : palette.tx2)
                }
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(vm.historyOpen ? palette.bgh : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).hoverHighlight(palette.bgh)
            Button { vm.clearCurrentChat() } label: {
                SageGlyphIcon(.trash, size: 15, color: palette.tx2)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).hoverHighlight(palette.bgh).help(s.chat.clearChat)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.bd).frame(height: 1) }
    }

    private var isVaultContext: Bool { if case .vault = vm.context { return true } else { return false } }

    private var contextChip: some View {
        HStack(spacing: 7) {
            Image(systemName: vm.context.iconSymbol).font(.system(size: 11)).foregroundStyle(palette.ac)
            Text(contextLabel).font(.sage(12)).foregroundStyle(palette.tx)
            if !isVaultContext {
                Button { onClearContext() } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(palette.tx3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 11)
        .background(palette.acs, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.ac.opacity(0.28), lineWidth: 1))
    }

    private var contextLabel: String {
        switch vm.context {
        case .vault: s.chat.ctxVault
        case let .file(name, _): name
        case let .folder(name, count, _): "\(name) · \(count)"
        case .selection: s.chat.ctxSelection
        }
    }

    /// Заголовок секции истории — простой caption-текст (по макету Секция 03), БЕЗ фона.
    /// В светлой теме bg==bg2==#FFFFFF, поэтому любой фон-блок бесполезен/чужероден; секции НЕ пиннятся
    /// (см. historyPanel) → непрозрачный фон не нужен.
    private func histHeader(_ text: String) -> some View {
        Text(text)
            .sageType(.caption).foregroundStyle(palette.tx3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10).padding(.bottom, 5)
    }

    /// Заголовок корзины времени → локализованная строка.
    private func bucketTitle(_ bucket: ChatHistory.Bucket) -> String {
        switch bucket {
        case .today: s.chat.histToday
        case .yesterday: s.chat.histYesterday
        case .earlier: s.chat.histEarlier
        }
    }

    /// Mono-подпись пути сессии (контекст → путь + счётчик файлов у папки).
    private func historySubtitle(_ ctx: ChatContext) -> String {
        let path = ctx.historyPath(vaultRoot: vaultRoot)
        if case let .folder(_, count, _) = ctx { return "\(path) · \(locale.language.filesCount(count))" }
        return path
    }

    @ViewBuilder private func historyTypeIcon(_ ctx: ChatContext) -> some View {
        switch ctx {
        case .vault: SparkMark(size: 14, color: palette.ac)
        case .folder: SageGlyphIcon(.folderClosed, size: 15, color: palette.ac)
        default: SageGlyphIcon(.fileDoc, size: 14, color: palette.tx2)
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            histHeader(s.chat.historyHeader.uppercased())
                .padding(.horizontal, 16)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if vm.sessions.isEmpty {
                            historyEmpty
                        } else {
                            ForEach(ChatHistory.group(vm.sessions, now: Date()), id: \.bucket) { group in
                                Section {
                                    ForEach(group.sessions) { session in historyRow(session) }
                                } header: { histHeader(bucketTitle(group.bucket).uppercased()) }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.hidden)
                .focusable()
                .focusEffectDisabled()
                .focused($histFocused)
                .onMoveCommand { dir in
                    guard !vm.sessions.isEmpty else { return }
                    if dir == .down { histCursor = min(vm.sessions.count - 1, histCursor + 1) }
                    else if dir == .up { histCursor = max(0, histCursor - 1) }
                    if vm.sessions.indices.contains(histCursor) {
                        withAnimation(SageMotion.quick) { proxy.scrollTo(vm.sessions[histCursor].id, anchor: .center) }
                    }
                }
                .onKeyPress(.return) {
                    guard vm.sessions.indices.contains(histCursor) else { return .ignored }
                    onOpenSession(vm.sessions[histCursor]); return .handled
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.bd).frame(height: 1) }
    }

    private func historyRow(_ session: ChatSession) -> some View {
        let idx = vm.sessions.firstIndex { $0.id == session.id } ?? -1
        return HStack(spacing: 11) {
            Button { onOpenSession(session) } label: {
                HStack(spacing: 12) {
                    historyTypeIcon(session.context)
                        .frame(width: 30, height: 30)
                        .background(typeIconBg(session.context), in: RoundedRectangle(cornerRadius: Radius.xs))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).font(.sage(13.5, .medium)).foregroundStyle(palette.tx).lineLimit(1)
                        Text(historySubtitle(session.context))
                            .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(palette.tx3).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Formatting.relativeOrJustNow(session.updatedAt, justNow: s.common.justNow,
                                                      locale: Locale(identifier: locale.language.localeIdentifier)))
                        .font(.sage(11.5)).foregroundStyle(palette.tx3).fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                vm.deleteSession(session)
            } label: {
                SageGlyphIcon(.trash, size: 14, color: palette.tx3).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(s.common.delete)
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background((histFocused && idx == histCursor) ? palette.bgh : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
        .hoverHighlight(palette.bgh)
        .id(session.id)
    }

    private func typeIconBg(_ ctx: ChatContext) -> Color {
        switch ctx {
        case .vault, .folder: palette.acs
        default: palette.bg3
        }
    }

    private var historyEmpty: some View {
        VStack(spacing: 0) {
            ZStack {
                SageGlyphIcon(.clockLarge, size: 27, color: palette.ac)
                    .frame(width: 54, height: 54).background(palette.acs, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                SparkMark(size: 13, color: palette.ac)
                    .frame(width: 19, height: 19).background(palette.bg, in: Circle())
                    .offset(x: 20, y: -20)
            }
            Text(s.chat.histEmptyTitle).font(.sage(16, .bold)).foregroundStyle(palette.tx).padding(.top, 16)
            Text(s.chat.histEmptyBody).font(.sage(12.5)).foregroundStyle(palette.tx2)
                .multilineTextAlignment(.center).lineSpacing(2).frame(maxWidth: 300).padding(.top, 7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 14)
    }

    // MARK: - Сообщения

    private var isEmptyState: Bool {
        !vm.isLoadingSession && vm.messages.isEmpty && !vm.isBusy && !vm.isThinking && !vm.isError
    }

    @ViewBuilder private var messagesList: some View {
        if isEmptyState {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.messages) { message in
                            bubble(message, streaming: vm.isBusy && message.id == vm.messages.last?.id && message.role == .assistant)
                        }
                        if vm.isThinking { thinkingBubble }
                        if vm.isError { errorBubble }
                        if vm.isBusy { stopButton }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22).padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: vm.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: vm.streamTick) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .task { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            SparkMark(size: 26, color: palette.ac)
                .frame(width: 52, height: 52)
                .background(palette.acs, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(s.chat.askTitle).font(.sage(19, .bold)).foregroundStyle(palette.tx).padding(.top, 18)
            Text(s.chat.askBody).font(.sage(13)).foregroundStyle(palette.tx2)
                .multilineTextAlignment(.center).lineSpacing(2).frame(maxWidth: 300).padding(.top, 7)
            VStack(spacing: 9) {
                suggestionChip("✦", s.chat.suggest1)
                suggestionChip("🔑", s.chat.suggest2)
                suggestionChip("❓", s.chat.suggest3)
            }
            .frame(maxWidth: 300).padding(.top, 22)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    private func suggestionChip(_ icon: String, _ text: String) -> some View {
        SuggestionChip(icon: icon, text: text) { vm.sendPrompt(text) }
    }

    /// Сообщение: юзер — правый акцентный пузырь; ассистент — документ (без пузыря) с hover-действиями.
    @ViewBuilder private func bubble(_ message: ChatMessage, streaming: Bool) -> some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 40)
                Text(message.text).sageType(.ui).foregroundStyle(palette.onAccent)
                    .textSelection(.enabled)
                    .padding(.vertical, 11).padding(.horizontal, 15)
                    .background(palette.ac, in: UnevenRoundedRectangle(
                        topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4, topTrailingRadius: 14, style: .continuous))
                    .frame(maxWidth: 480, alignment: .trailing)
            }
        } else if isStatusLine(message.text) {
            statusChip(message.text)
        } else {
            AssistantMessage(message: message, streaming: streaming, markdown: markdown,
                             copyTitle: s.chat.copy, retryTitle: s.chat.retry, onRetry: { vm.retry() })
        }
    }

    /// Статус действия ИИ (создал/обновил/удалил…) — короткая строка, рендерим компактным чипом.
    private func isStatusLine(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["📁", "📄", "✍️", "✏️", "🗑"].contains { t.hasPrefix($0) }
    }

    private func statusChip(_ text: String) -> some View {
        HStack(spacing: 0) {
            Text(text).font(.sage(12)).foregroundStyle(palette.tx2).lineLimit(1)
                .padding(.vertical, 6).padding(.horizontal, 11)
                .background(palette.bg2, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.bd, lineWidth: 1))
            Spacer(minLength: 0)
        }
    }

    private func avatar(isUser: Bool) -> some View {
        Group {
            if isUser {
                Text("Я").font(.sage(11, .semibold)).foregroundStyle(palette.tx)
            } else {
                SparkMark(size: 14, color: palette.ac)
            }
        }
        .frame(width: 27, height: 27)
        .background(isUser ? palette.bg3 : palette.acs, in: RoundedRectangle(cornerRadius: Radius.xs))
    }

    private var thinkingBubble: some View {
        HStack(spacing: 11) {
            avatar(isUser: false)
            TypingDots()
                .padding(.vertical, 13).padding(.horizontal, 16)
                .background(palette.bg2, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(palette.bd, lineWidth: 1))
            Spacer(minLength: 40)
        }
    }

    private var errorBubble: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("!").font(.sage(13, .bold)).foregroundStyle(palette.error)
                .frame(width: 27, height: 27).background(palette.error.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.xs))
            VStack(alignment: .leading, spacing: 10) {
                Text(s.chat.errorMsg).font(.sage(13)).foregroundStyle(palette.error)
                Button { vm.retry() } label: {
                    HStack(spacing: 6) { Image(systemName: "arrow.clockwise"); Text(s.chat.retry) }
                        .font(.sage(12, .semibold)).foregroundStyle(palette.onAccent)
                        .padding(.vertical, 6).padding(.horizontal, 13)
                        .background(palette.ac, in: RoundedRectangle(cornerRadius: Radius.sm))
                }.buttonStyle(.plain)
            }
            .padding(12)
            .background(palette.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(palette.error.opacity(0.28), lineWidth: 1))
            Spacer(minLength: 40)
        }
    }

    private var stopButton: some View {
        HStack {
            Spacer()
            Button { vm.stop() } label: {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.tx2).frame(width: 9, height: 9)
                    Text(s.chat.stopGen).font(.sage(12)).foregroundStyle(palette.tx2)
                }
                .padding(.vertical, 6).padding(.horizontal, 13)
                .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd2, lineWidth: 1))
            }.buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 9) {
            if let pending = vm.pendingDeletion {
                deletionCard(pending)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !voiceOverlayActive {
                HStack(alignment: .bottom, spacing: 9) {
                    TextField("", text: Binding(get: { vm.input }, set: { vm.input = $0 }), axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.tx)
                        .focused($inputFocused)
                        .sagePlaceholder(s.chat.placeholder, when: vm.input.isEmpty)
                        .lineLimit(1 ... 4)
                        .onSubmit { vm.send() }
                        .padding(.vertical, 3)
                        .id(themeKey)
                    if vm.whisperAvailable {
                        iconButton(icon: "mic", active: vm.voice != .off) { vm.toggleVoice() }
                    }
                    Button { vm.send() } label: {
                        Image(systemName: "paperplane.fill").font(.system(size: 14))
                            .foregroundStyle(palette.onAccent)
                            .frame(width: 34, height: 34).background(palette.ac, in: RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain).disabled(!vm.canSend).opacity(vm.canSend ? 1 : 0.5)
                }
                .padding(.vertical, 9).padding(.leading, 15).padding(.trailing, 9)
                .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.bd2, lineWidth: 1))
            }
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22).padding(.bottom, 20)
        .animation(SageMotion.smooth, value: vm.pendingDeletion != nil)
    }

    private func deletionCard(_ pending: ChatViewModel.PendingDeletion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(palette.error)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.chat.deletePrompt).font(.sage(13, .medium)).foregroundStyle(palette.tx)
                Text("«\(pending.title)»").font(.sage(12)).foregroundStyle(palette.tx2)
            }
            Spacer()
            Button { vm.cancelDeletion() } label: {
                Text(s.common.cancel).font(.sage(12)).foregroundStyle(palette.tx2)
                    .padding(.vertical, 6).padding(.horizontal, 13)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
            }.buttonStyle(.plain)
            Button { vm.confirmDeletion(deletedText: "🗑 \(s.chat.deleted) «\(pending.title)»") } label: {
                Text(s.common.delete).font(.sage(12, .semibold)).foregroundStyle(.white)
                    .padding(.vertical, 6).padding(.horizontal, 13)
                    .background(palette.error, in: RoundedRectangle(cornerRadius: Radius.sm))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 11).padding(.horizontal, 15)
        .background(palette.error.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.error.opacity(0.3), lineWidth: 1))
    }

    private func iconButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundStyle(active ? palette.ac : palette.tx2)
                .frame(width: 34, height: 34)
                .background(active ? palette.acs : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}

/// Ответ ассистента как ДОКУМЕНТ (без пузыря): spark-аватар + текст + hover-действия Копировать/Повторить.
private struct AssistantMessage: View {
    let message: ChatMessage
    let streaming: Bool
    let markdown: MarkdownRendering
    let copyTitle: String
    let retryTitle: String
    let onRetry: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false
    /// Раскрытие печатью завершено → свопаем на форматированный markdown.
    @State private var revealDone = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            SparkMark(size: 14, color: palette.ac)
                .frame(width: 27, height: 27)
                .background(palette.acs, in: RoundedRectangle(cornerRadius: Radius.xs))
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if streaming || !revealDone {
                        StreamingText(message.text, active: streaming, font: .sage(14), color: palette.tx,
                                      onComplete: { revealDone = true })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownBlocksView(markdown.render(message.text))
                    }
                }
                .textSelection(.enabled)
                .onAppear { if !streaming { revealDone = true } }
                if !streaming, revealDone {
                    HStack(spacing: 6) {
                        actionChip(icon: "doc.on.doc", title: copyTitle) { Pasteboard.copy(message.text) }
                        actionChip(icon: "arrow.clockwise", title: retryTitle, action: onRetry)
                    }
                    .padding(.top, 12)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                }
            }
            Spacer(minLength: 40)
        }
        .onHover { hovering = $0 }
    }

    private func actionChip(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.sage(11.5))
            }
            .foregroundStyle(palette.tx2)
            .padding(.vertical, 4).padding(.horizontal, 9)
            .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(palette.bd, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.bgh, radius: Radius.xs)
    }
}

/// Высота области чата — для «шторы» истории (offset-выезд на всю высоту).
private struct ChatAreaHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Чип-подсказка пустого стейта. Hover МЕНЯЕТ САМ фон (bg1→bgh) — раньше `.hoverHighlight`
/// был под собственным фоном bg1 лейбла и не был виден.
private struct SuggestionChip: View {
    let icon: String
    let text: String
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(icon).font(.system(size: 13)).foregroundStyle(palette.tx2)
                    .frame(width: 18, alignment: .center)
                Text(text).font(.sage(12.5)).foregroundStyle(palette.tx2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? palette.bgh : palette.bg1, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(hovering ? palette.bd2 : palette.bd, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
