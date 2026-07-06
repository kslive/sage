import AppKit
import Combine
import CoreKit
import DesignSystem
import Localization
import SwiftUI

public struct EditorView: View {
    @State private var vm: EditorViewModel
    @State private var webCtrl = WebEditorController()
    @AppStorage("sage.outlineWidth") private var outlineWidthRaw: Double = 210
    @State private var lastAIAction: AIAction = .ask
    @State private var selText = ""
    @State private var savedHadSelection = false
    @State private var applyPending = false
    @State private var showApplied = false
    @State private var aiAnswerHeight: CGFloat = 0
    @Namespace private var aiMorph
    @State private var linkPickerOpen = false
    @State private var linkAnchor: CGRect?
    @State private var linkVM: LinkInsertViewModel?
    @State private var webViewReady = false
    private let mode: EditorMode
    private let variant: EditorVariant
    private let spellcheck: Bool
    private let vault: VaultServicing
    private let vaultRoot: URL?
    private let onCreate: () -> Void
    private let onOpenFolder: () -> Void
    private let onOpenNote: (URL) -> Void
    private let onSelectionChanged: (String) -> Void
    private let aiInvokeNonce: Int
    private let vaultHasNotes: Bool
    private let fileURL: URL?

    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale
    @FocusState private var aiFocused: Bool
    private enum LinkField { case text, url, query }
    @FocusState private var linkFocus: LinkField?

    /// Ключ идентичности темы — меняется при смене схемы/акцента (для .id, пересоздающего NSTextField).
    /// `"\(Color)"` на macOS не различим между темами → берём стабильный `palette.key` (isDark+accent).
    private var themeKey: String { palette.key }

    public init(
        fileURL: URL?, mode: EditorMode, variant: EditorVariant,
        vault: VaultServicing, markdown: MarkdownRendering, ai: AICoordinating,
        spellcheck: Bool, onCreate: @escaping () -> Void, onOpenFolder: @escaping () -> Void,
        onOpenNote: @escaping (URL) -> Void = { _ in }, aiInvokeNonce: Int = 0,
        vaultHasNotes: Bool = false, vaultRoot: URL? = nil,
        onSelectionChanged: @escaping (String) -> Void = { _ in },
        tasks: AITaskRegistry? = nil
    ) {
        self.aiInvokeNonce = aiInvokeNonce
        self.vaultHasNotes = vaultHasNotes
        self.vault = vault
        self.vaultRoot = vaultRoot
        self.onSelectionChanged = onSelectionChanged
        self.fileURL = fileURL
        _vm = State(wrappedValue: EditorViewModel(fileURL: fileURL, vault: vault, markdown: markdown, ai: ai, tasks: tasks))
        self.mode = mode
        self.variant = variant
        self.spellcheck = spellcheck
        self.onCreate = onCreate
        self.onOpenFolder = onOpenFolder
        self.onOpenNote = onOpenNote
    }

    private var s: Strings { locale.strings }

    /// JSON подписей слэш-меню (ключ→текст) для моста в webview — иначе пункты «/» были на русском.
    private var slashStringsJSON: String {
        let sl = s.slash
        let dict: [String: String] = [
            "blkText": sl.blkText, "blkH1": sl.blkH1, "blkH2": sl.blkH2, "blkH3": sl.blkH3,
            "blkBullet": sl.blkBullet, "blkNumbered": sl.blkNumbered, "blkCheck": sl.blkCheck,
            "blkQuote": sl.blkQuote, "blkTable": sl.blkTable, "blkCode": sl.blkCode,
            "blkDivider": sl.blkDivider, "blkLink": sl.blkLink, "tableColumn": sl.tableColumn,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    public var body: some View {
        Group {
            if fileURL == nil {
                if vaultHasNotes { noSelectionState } else { emptyState }
            } else {
                editorBody
            }
        }
        .task { await vm.load() }
        .onChange(of: fileURL) { _, new in
            applyPending = false
            webCtrl.clearMark()
            webCtrl.beginSwitch()
            Task { await vm.switchTo(new) }
        }
        .onChange(of: aiInvokeNonce) { _, _ in if vm.fileURL != nil { openAI() } }
        .onChange(of: vm.scrollTarget) { _, t in if let t { webCtrl.scrollToHeading(t) } }
        .onChange(of: vm.aiStreaming) { _, streaming in if !streaming, applyPending { finishAI() } }
        .onReceive(NotificationCenter.default.publisher(for: .sageVaultChanged)) { note in
            guard let url = note.userInfo?["url"] as? URL,
                  (note.userInfo?["created"] as? Bool) != true,
                  let open = vm.fileURL,
                  url.standardizedFileURL == open.standardizedFileURL else { return }
            Task { await vm.load(); webCtrl.setDoc(vm.text) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageGitSyncBegan)) { _ in vm.gitSyncBegan() }
        .onReceive(NotificationCenter.default.publisher(for: .sageGitSynced)) { _ in
            Task {
                guard !vm.gitSyncEnded() else { return }
                if await vm.reconcileExternal() { webCtrl.setDoc(vm.text) }
            }
        }
        .onDisappear { vm.flushSave(); vm.cancelInFlightAI() }
        .onReceive(NotificationCenter.default.publisher(for: .sageFlushAll)) { _ in vm.flushSave() }
        .onChange(of: locale.language) { _, _ in webCtrl.setStrings(slashStringsJSON) }
    }

    private var editorBody: some View {
        HStack(spacing: 0) {
            editorSurface
            if variant == .b { outlineRail }
        }
    }

    private var editorSurface: some View {
            ZStack(alignment: .bottom) {
                palette.bg
                WebEditorView(
                    text: Binding(get: { vm.text }, set: { vm.onEditorText($0) }),
                    previewMode: mode == .preview,
                    palette: palette,
                    controller: webCtrl,
                    baseFolder: vm.fileURL?.deletingLastPathComponent().path,
                    onSelection: { sel in selText = sel; onSelectionChanged(sel) },
                    onOpenLink: { href in handleLink(href) },
                    onRequestAI: { openAI() },
                    onRequestLink: { rect in openLinkPicker(anchor: rect) },
                    onEscape: { if vm.aiBarOpen { closeAI() } },
                    onSaveImage: { data, ext in await vm.saveAsset(data, ext: ext) },
                    onFlushDoc: { vm.flushSave() },
                    onReady: {
                        withAnimation(.easeOut(duration: 0.25)) { webViewReady = true }
                        webCtrl.setStrings(slashStringsJSON)
                    }
                )
                if !webViewReady {
                    editorLoadingPlaceholder.transition(.opacity)
                }
                if vm.aiBarOpen {
                    aiOverlay.transition(.opacity)
                } else {
                    floatingAIBar.transition(.opacity)
                }
                if linkPickerOpen { linkPicker.transition(.opacity) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: vm.aiBarOpen)
            .overlay(alignment: .top) { appliedToast }
    }

    /// Шиммер-скелет на время холодного старта webview (чтобы не видеть тёмный экран).
    /// АДАПТИВНЫЙ: ширина колонки = по доступному месту (не фикс 620) → помещается в любое окно,
    /// не распирает узкое. Полоски — доли ширины колонки.
    private var editorLoadingPlaceholder: some View {
        let fracs: [CGFloat] = [0.97, 0.87, 0.76, 0.94, 0.81, 0.53, 0.90, 0.68, 0.79, 0.87]
        return GeometryReader { geo in
            let colW = max(180, min(620, geo.size.width - 120))
            ZStack(alignment: .top) {
                palette.bg
                VStack(alignment: .leading, spacing: 13) {
                    SkeletonBar(width: colW * 0.42, height: 24)
                    Color.clear.frame(height: 10)
                    ForEach(Array(fracs.enumerated()), id: \.offset) { _, f in
                        SkeletonBar(width: max(40, colW * f), height: 12)
                    }
                }
                .frame(width: colW, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.top, 52)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleLink(_ href: String) {
        if let scheme = URL(string: href)?.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "mailto" {
            if let url = URL(string: href) { NSWorkspace.shared.open(url) }
            return
        }
        let decoded = href.normalizedLinkTarget
        let fm = FileManager.default
        for baseDir in [vaultRoot, vm.fileURL?.deletingLastPathComponent()].compactMap({ $0 }) {
            let cand = URL(fileURLWithPath: decoded, relativeTo: baseDir).standardizedFileURL
            if fm.fileExists(atPath: cand.path) { onOpenNote(cand); return }
            let withMd = cand.pathExtension.isEmpty ? cand.appendingPathExtension("md") : cand
            if fm.fileExists(atPath: withMd.path) { onOpenNote(withMd); return }
        }
        guard let root = vaultRoot else { return }
        let leaf = ((decoded as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        if !leaf.isEmpty, let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension == "md" {
                if u.deletingPathExtension().lastPathComponent.lowercased() == leaf { onOpenNote(u); return }
            }
        }
    }

    // MARK: - Slash «Ссылка»: выбор заметки

    private func openLinkPicker(anchor: CGRect? = nil) {
        linkAnchor = anchor
        let model = LinkInsertViewModel(selectedText: webCtrl.selectedText, vault: vault,
                                        vaultRoot: vaultRoot, currentFile: vm.fileURL)
        linkVM = model
        Task {
            await model.load()
            withAnimation(.easeOut(duration: 0.18)) { linkPickerOpen = true }
        }
    }

    private func closeLinkPicker() {
        linkPickerOpen = false
        linkVM = nil
    }

    /// Вставить готовую markdown-ссылку (заменяет выделение) и закрыть поповер.
    private func insertLinkText(_ text: String) {
        webCtrl.insertText(text)
        closeLinkPicker()
    }

    @ViewBuilder private var linkPicker: some View {
        if let linkVM { linkPopover(linkVM) }
    }

    private func linkPopover(_ lm: LinkInsertViewModel) -> some View {
        @Bindable var lm = lm
        return ZStack {
            Color.black.opacity(palette.isDark ? 0.18 : 0.07).contentShape(Rectangle()).onTapGesture { closeLinkPicker() }
            Button("", action: closeLinkPicker).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            VStack(alignment: .leading, spacing: 12) {
                SageSegmented(
                    [SegmentItem(tag: LinkInsertViewModel.Mode.url, label: s.slash.linkURL),
                     SegmentItem(tag: LinkInsertViewModel.Mode.note, label: s.slash.linkNote)],
                    selection: $lm.mode, accentSelected: true)
                linkField(s.slash.linkText, text: $lm.text).focused($linkFocus, equals: .text)
                    .onSubmit { submitLink(lm) }
                if lm.mode == .url {
                    linkField("URL", text: $lm.url).focused($linkFocus, equals: .url)
                        .onSubmit { submitLink(lm) }
                    HStack(spacing: 8) {
                        Spacer()
                        SageButton(s.common.cancel, kind: .secondary) { closeLinkPicker() }
                        SageButton(s.slash.linkAdd) { submitLink(lm) }
                    }
                    .opacity(lm.canAddURL ? 1 : 0.6)
                    .allowsHitTesting(lm.canAddURL)
                } else {
                    linkField(s.nav.search, text: $lm.query).focused($linkFocus, equals: .query)
                        .onSubmit { submitLink(lm) }
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(lm.filteredNotes) { hit in
                                Button { insertLinkText(lm.noteLink(hit.url)) } label: {
                                    HStack(spacing: 8) {
                                        SageGlyphIcon(.fileDoc, size: 14, color: palette.tx3)
                                        Text(hit.title).font(.sage(13, .medium)).foregroundStyle(palette.tx).lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(hit.relPath).font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(palette.tx3).lineLimit(1)
                                    }
                                    .padding(.vertical, 7).padding(.horizontal, 10).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).hoverHighlight(palette.bgh, radius: Radius.xs)
                            }
                            if let create = lm.createSuggestion {
                                Button { Task { if let link = await lm.createAndLink() { insertLinkText(link) } } } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle").font(.system(size: 13)).foregroundStyle(palette.ac)
                                        Text("\(s.slash.linkCreate) «\(create)»").font(.sage(12.5)).foregroundStyle(palette.ac)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 8).padding(.horizontal, 10).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).hoverHighlight(palette.bgh, radius: Radius.xs)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(16)
            .frame(width: 440)
            .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.bd2, lineWidth: 1))
            .sageElevation(palette)
            .onExitCommand { closeLinkPicker() }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    if lm.text.trimmingCharacters(in: .whitespaces).isEmpty { linkFocus = .text }
                    else { linkFocus = lm.mode == .url ? .url : .query }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Enter в поповере = подтвердить (с валидацией): URL-режим — добавить если URL не пуст;
    /// режим заметки — выбрать первую найденную / создать предложенную.
    private func submitLink(_ lm: LinkInsertViewModel) {
        if lm.mode == .url {
            guard lm.canAddURL else { return }
            insertLinkText(lm.buildURLLink())
        } else if let hit = lm.filteredNotes.first {
            insertLinkText(lm.noteLink(hit.url))
        } else if lm.createSuggestion != nil {
            Task { if let link = await lm.createAndLink() { insertLinkText(link) } }
        }
    }

    private func linkField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain).font(.sage(13.5))
            .foregroundStyle(palette.tx)
            .sagePlaceholder(placeholder, when: text.wrappedValue.isEmpty)
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(palette.inp, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
            .id(themeKey)
    }

    // MARK: - Outline rail (вариант B)

    private var outlineRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.app.outline.uppercased()).sageType(.caption).foregroundStyle(palette.tx3).padding(.bottom, 12)
            ForEach(vm.outline) { item in
                Button { vm.scrollTarget = item.text } label: {
                    Text(item.text)
                        .font(.sage(12.5))
                        .foregroundStyle(item.level == 1 ? palette.tx : palette.tx2)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(item.level - 1) * 12)
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(palette.bgh, radius: Radius.xs)
            }
            Divider().overlay(palette.bd).padding(.vertical, 14)
            Text(s.app.info.uppercased()).sageType(.caption).foregroundStyle(palette.tx3).padding(.bottom, 10)
            infoRow(s.app.words, "\(vm.wordCount)")
            infoRow(s.app.edited, editedTime)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 20)
        .frame(width: CGFloat(outlineWidthRaw))
        .overlay(alignment: .leading) { Rectangle().fill(palette.bd).frame(width: 1) }
        .overlay(alignment: .leading) {
            ResizeHandle(width: Binding(get: { CGFloat(outlineWidthRaw) }, set: { outlineWidthRaw = Double($0) }), min: 180, max: 340, invert: true)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.sage(12)).foregroundStyle(palette.tx2)
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(palette.tx).monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    private var editedTime: String {
        guard let date = vm.modifiedAt else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Инлайн-ИИ (без кнопок: трансформация / вставка у каретки)

    private func openAI() {
        lastAIAction = .ask
        vm.aiBarOpen = true
        webCtrl.markSelection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { aiFocused = true }
    }

    private func closeAI() { webCtrl.clearMark(); applyPending = false; aiAnswerHeight = 0; vm.dismissAI() }

    private func submitAI() {
        let prompt = vm.aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        savedHadSelection = !webCtrl.selectedText.isEmpty
        if savedHadSelection, EditorViewModel.isPureDeletion(prompt) {
            webCtrl.replaceSelection("")
            vm.scheduleSave()
            webCtrl.clearMark()
            vm.dismissAI()
            flashApplied()
            vm.aiPrompt = ""
            return
        }
        let intent = EditorViewModel.inlineIntent(prompt, hasSelection: savedHadSelection)
        let fileOp = !savedHadSelection && mentionsFileOp(prompt)
        let action: AIAction = (intent == .edit && !fileOp) ? .transform : .ask
        lastAIAction = action
        applyPending = true
        vm.runAI(action, selection: webCtrl.selectedText)
        vm.aiPrompt = ""
    }

    /// Промпт про операции с ФАЙЛАМИ/папками (инлайн их не умеет — это работа чата).
    private func mentionsFileOp(_ raw: String) -> Bool {
        let p = raw.lowercased()
        let obj = ["файл", "папк", "заметк", "file", "folder", "note"]
        let verb = ["удали", "создай", "переимен", "перемест", "delete", "create", "rename", "move", "remove"]
        return obj.contains { p.contains($0) } && verb.contains { p.contains($0) }
    }

    /// Завершение генерации: edit → применить к документу (пусто=удалить выделение);
    /// answer → оставить ответ в карточке, ничего не применять.
    private func finishAI() {
        applyPending = false
        guard !vm.aiError else { return }
        guard vm.aiApplyMode == .edit else { return }
        let result = vm.aiResult
        if savedHadSelection {
            webCtrl.replaceSelection(result)
        } else if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            webCtrl.insertAtCursor(result)
        } else {
            vm.dismissAI(); return
        }
        vm.scheduleSave()
        webCtrl.clearMark()
        vm.dismissAI()
        flashApplied()
    }

    private func flashApplied() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showApplied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.35)) { showApplied = false }
        }
    }

    private var aiLoadingLabel: String {
        switch lastAIAction {
        case .ask, .transform: s.app.aiThinking
        case .improve: s.app.aiImproving
        case .continueText: s.app.aiContinuing
        case .summary: s.app.aiSummarizing
        }
    }

    @ViewBuilder private var appliedToast: some View {
        if showApplied {
            HStack(spacing: 6) {
                SparkMark(size: 12, color: palette.ac)
                Text(s.app.aiApplied).font(.sage(12, .medium)).foregroundStyle(palette.tx)
            }
            .padding(.vertical, 7).padding(.horizontal, 12)
            .background(palette.bg2, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.ac, lineWidth: 1))
            .sageElevation(palette)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var floatingAIBar: some View {
        AskSagePill(s.app.askInline) { openAI() }
            .matchedGeometryEffect(id: "aibar", in: aiMorph)
            .padding(.bottom, 20)
    }

    @ViewBuilder private var aiOverlay: some View {
        if vm.aiBarOpen {
            VStack(spacing: 10) {
                if vm.aiError || (vm.aiStreaming && vm.aiResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    HStack(spacing: 8) {
                        if vm.aiError {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(palette.tx2)
                            Text(s.app.aiFailed).font(.sage(12.5)).foregroundStyle(palette.tx2)
                        } else {
                            TypingDots(color: palette.ac)
                            Text(aiLoadingLabel).font(.sage(12.5)).foregroundStyle(palette.ac)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 18)
                    .frame(maxWidth: 660)
                    .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .aiGlowBorder(active: vm.aiStreaming, cornerRadius: Radius.lg)
                    .sageElevation(palette)
                }
                if !vm.aiResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        Group {
                            if vm.aiStreaming {
                                StreamingText(vm.aiResult, active: true, font: .sage(14), color: palette.tx)
                            } else {
                                MarkdownBlocksView(vm.renderer.render(vm.aiResult))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: AIAnswerHeightKey.self, value: g.size.height)
                        })
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: min(max(aiAnswerHeight, 24), 300))
                    .onPreferenceChange(AIAnswerHeightKey.self) { aiAnswerHeight = $0 }
                    .padding(.vertical, 12).padding(.horizontal, 18)
                    .frame(maxWidth: 660)
                    .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .aiGlowBorder(active: vm.aiStreaming, cornerRadius: Radius.lg)
                    .sageElevation(palette)
                }
                HStack(spacing: 9) {
                    SparkMark(size: 15, color: palette.ac)
                    TextField("", text: $vm.aiPrompt)
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.tx)
                        .tint(palette.ac)
                        .sagePlaceholder(s.slash.aiAsk, when: vm.aiPrompt.isEmpty)
                        .id(themeKey)
                        .focused($aiFocused)
                        .onSubmit { submitAI() }
                        .onExitCommand { closeAI() }
                    Button { closeAI() } label: {
                        Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(palette.tx3)
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 11).padding(.horizontal, 18)
                .frame(maxWidth: 660)
                .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.bd2, lineWidth: 1))
                .sageElevation(palette)
                .matchedGeometryEffect(id: "aibar", in: aiMorph)
                .onChange(of: themeKey) { _, _ in if vm.aiBarOpen { aiFocused = true } }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .background {
                Button("", action: closeAI).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Состояния

    private var emptyState: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bg2)
                .frame(width: 64, height: 64)
                .overlay(Text("📄").font(.sage(28)))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.bd, lineWidth: 1))
                .padding(.bottom, 18)
            Text(s.app.emptyVaultTitle).sageType(.h2).foregroundStyle(palette.tx).padding(.bottom, 7)
            Text(s.app.emptyVaultBody).sageType(.body).foregroundStyle(palette.tx2)
                .multilineTextAlignment(.center).frame(maxWidth: 360).padding(.bottom, 22)
            HStack(spacing: 10) {
                SageButton(s.app.newNote, icon: "plus", action: onCreate)
                SageButton(s.app.openFolder, kind: .secondary, icon: "folder", action: onOpenFolder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionState: some View {
        VStack(spacing: 0) {
            SparkLogo(size: 30, color: palette.ac).opacity(0.7).padding(.bottom, 18)
            Text(s.app.noSelectionTitle).sageType(.h2).foregroundStyle(palette.tx).padding(.bottom, 7)
            Text(s.app.noSelectionBody).sageType(.body).foregroundStyle(palette.tx2)
                .multilineTextAlignment(.center).frame(maxWidth: 360).padding(.bottom, 22)
            SageButton(s.app.newNote, icon: "plus", action: onCreate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Измерение высоты контента ответа ИИ для роста облачка по тексту до максимума.
private struct AIAnswerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
