import CoreKit
import DesignSystem
import Localization
import SettingsStore
import SwiftUI

public struct SettingsView: View {
    @Binding private var tab: SettingsTab
    @State private var vm: SettingsViewModel
    private let updaterVM: UpdaterViewModel
    @AppStorage("sage.settingsNavWidth") private var navWidthRaw: Double = 210
    private let onChangeVault: () -> Void

    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale
    @Environment(ThemeManager.self) private var theme
    @Environment(SettingsStore.self) private var settings

    public init(
        tab: Binding<SettingsTab>, models: ModelManaging, git: GitServicing, updaterVM: UpdaterViewModel,
        settings: SettingsStore, onChangeVault: @escaping () -> Void,
        onToast: @escaping (String, String, Bool) -> Void
    ) {
        _tab = tab
        self.onChangeVault = onChangeVault
        self.updaterVM = updaterVM
        _vm = State(wrappedValue: SettingsViewModel(models: models, git: git, settings: settings, onToast: onToast))
    }

    private var s: Strings { locale.strings }

    public var body: some View {
        HStack(spacing: 0) {
            tabNav
            ResizeHandle(width: Binding(get: { CGFloat(navWidthRaw) }, set: { navWidthRaw = Double($0) }), min: 178, max: 280)
            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 40).padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .task { await vm.loadStates() }
        .onAppear { vm.strings = s }
        .onChange(of: locale.language) { _, _ in vm.strings = s }
    }

    private var tabNav: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(s.settings.title.uppercased()).sageType(.caption).foregroundStyle(palette.tx3)
                .padding(.horizontal, 8).padding(.bottom, 10)
            ForEach(SettingsTab.allCases) { item in
                Button { tab = item } label: {
                    HStack(spacing: 10) {
                        tabIcon(item).frame(width: 16)
                        Text(tabTitle(item)).font(.sage(13)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == item ? palette.tx : palette.tx2)
                    .padding(.horizontal, 9).padding(.vertical, 8)
                    .background(tab == item ? palette.bgh : .clear, in: RoundedRectangle(cornerRadius: Radius.xs))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(palette.bgh, radius: Radius.xs)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 18)
        .frame(width: CGFloat(navWidthRaw))
        .overlay(alignment: .trailing) { Rectangle().fill(palette.bd).frame(width: 1) }
    }

    @ViewBuilder private func tabIcon(_ item: SettingsTab) -> some View {
        if item == .ai {
            SparkMark(size: 14, color: tab == item ? palette.tx : palette.tx2)
        } else {
            Image(systemName: item.iconSymbol).font(.system(size: 13))
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general: generalTab
        case .ai: aiTab
        case .appearance: appearanceTab
        case .git: gitTab
        case .updates: updatesTab
        case .about: aboutTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            tabHeader(s.settings.general, s.settings.generalSub)
            settingRow(s.settings.language, s.settings.languageSub) {
                SageSegmented(
                    AppLanguage.allCases.map { SegmentItem(tag: $0, label: langCode($0)) },
                    selection: Binding(get: { locale.language }, set: { locale.setLanguage($0) }),
                    accentSelected: true
                )
            }
            settingRow(s.settings.vault, settings.vaultPath.isEmpty ? "—" : settings.vaultPath) {
                SageButton(s.settings.change, kind: .secondary, action: onChangeVault)
            }
            settingRow(s.settings.startup, s.settings.startupSub) { SageToggle(isOn: $settings.launchAtLogin) }
            settingRow(s.settings.spellcheck, s.settings.spellcheckSub, divider: false) { SageToggle(isOn: $settings.spellcheck) }
        }
    }

    // MARK: - AI

    private var aiTab: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            tabHeader(s.settings.ai, s.settings.aiSub)
            sectionLabel(s.settings.llmSection)
            VStack(spacing: 8) {
                ForEach(ModelCatalog.llms) { spec in
                    modelRow(id: spec.id, emoji: spec.emoji, name: spec.name,
                             size: Formatting.fileSize(spec.sizeBytes),
                             active: settings.activeLLMId == spec.id,
                             onActivate: { vm.activateLLM(spec.id) },
                             onDownload: { vm.downloadLLM(spec) })
                }
            }
            .padding(.bottom, 24)
            sectionLabel(s.settings.whisperSection)
            VStack(spacing: 8) {
                ForEach(ModelCatalog.whispers) { spec in
                    modelRow(id: spec.id, emoji: spec.emoji, name: spec.name,
                             size: Formatting.fileSize(spec.sizeBytes),
                             active: settings.activeWhisperId == spec.id,
                             onActivate: { vm.activateWhisper(spec.id) },
                             onDownload: { vm.downloadWhisper(spec) })
                }
            }
        }
    }

    private func modelRow(id: String, emoji: String, name: String, size: String, active: Bool, onActivate: @escaping () -> Void, onDownload: @escaping () -> Void) -> some View {
        let state = vm.state(id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(emoji).font(.sage(18))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(name).font(.sage(13, .semibold)).foregroundStyle(palette.tx)
                        if active, state.isInstalled { StatusDot(size: 7) }
                    }
                    Text(statusText(size: size, state: state, active: active)).font(.sage(11.5)).foregroundStyle(palette.tx3)
                }
                Spacer()
                trailingControl(state: state, active: active, onActivate: onActivate, onDownload: onDownload)
            }
            if case let .downloading(progress) = state {
                LinearProgress(fraction: progress.fraction).padding(.top, 10)
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 14)
        .background((active && state.isInstalled) ? palette.acs : palette.bg1, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder((active && state.isInstalled) ? palette.ac.opacity(0.4) : palette.bd, lineWidth: 1))
    }

    @ViewBuilder private func trailingControl(state: DownloadState, active: Bool, onActivate: @escaping () -> Void, onDownload: @escaping () -> Void) -> some View {
        switch state {
        case .installed:
            if active {
                Text(s.models.active).font(.sage(11.5)).foregroundStyle(palette.tx3)
            } else {
                SageButton(s.common.change, kind: .secondary, action: onActivate)
            }
        case .downloading, .verifying:
            SageSpinner(size: 16)
        case .failed:
            SageButton(s.ob.retry, action: onDownload)
        case .notInstalled:
            SageButton(s.settings.download, action: onDownload)
        }
    }

    private func statusText(size: String, state: DownloadState, active: Bool) -> String {
        switch state {
        case .notInstalled: "\(size) · \(s.models.notInstalled)"
        case let .downloading(p): "\(s.models.downloadingStatus) \(Formatting.progress(done: p.downloadedBytes, total: p.totalBytes))"
        case .verifying: s.ob.verifying
        case .installed: active ? "\(size) · \(s.models.active)" : "\(size) · \(s.models.installed)"
        case .failed: s.ob.dlErrorMsg
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabHeader(s.settings.appearance, s.settings.appearanceSub)
            Text(s.settings.theme).font(.sage(13.5, .medium)).foregroundStyle(palette.tx).padding(.bottom, 12)
            HStack(spacing: 12) {
                themeCard(.dark, s.theme.dark)
                themeCard(.light, s.theme.light)
                themeCard(.auto, s.theme.auto)
            }
            .padding(.bottom, 26)
            settingRow(s.settings.accent, s.settings.accentSub, divider: false) {
                HStack(spacing: 9) {
                    ForEach(AccentPreset.all) { preset in
                        Circle()
                            .fill(Color(hex: palette.isDark ? preset.darkHex : preset.lightHex))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(theme.accent.id == preset.id ? palette.tx : .clear, lineWidth: 2))
                            .onTapGesture { theme.accent = preset }
                    }
                }
            }
        }
    }

    private func themeCard(_ mode: AppTheme, _ label: String) -> some View {
        let selected = theme.mode == mode
        let isDarkPreview = mode == .dark || (mode == .auto && palette.isDark)
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                (isDarkPreview ? Color(hex: "#08090A") : Color(hex: "#FFFFFF"))
                RoundedRectangle(cornerRadius: 4).fill(isDarkPreview ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                    .frame(width: 26).padding(8)
            }
            .frame(height: 64)
            HStack {
                Text(label).font(.sage(12.5, .medium)).foregroundStyle(palette.tx)
                Spacer()
                Circle().strokeBorder(selected ? palette.ac : palette.bd2, lineWidth: 1.5).frame(width: 15, height: 15)
                    .overlay(Circle().fill(selected ? palette.ac : .clear).frame(width: 8, height: 8))
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
        }
        .background(palette.bg1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(selected ? palette.ac : palette.bd, lineWidth: 1.5))
        .onTapGesture { theme.mode = mode }
    }

    // MARK: - Git

    private var gitTab: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            tabHeader(s.settings.git, s.settings.gitSub)
            if vm.isGitConnected {
                gitConnected(settings: settings)
            } else {
                gitConnectForm
            }
        }
        .task { await vm.loadGit() }
    }

    private var gitConnectForm: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Text("🔗").font(.sage(24)).frame(width: 52, height: 52)
                    .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.bd, lineWidth: 1))
                Text(s.settings.gitConnectTitle).font(.sage(15, .semibold)).foregroundStyle(palette.tx)
                Text(s.settings.gitConnectSub).font(.sage(13)).foregroundStyle(palette.tx2).multilineTextAlignment(.center)
                TextField("", text: $vm.remoteInput)
                    .textFieldStyle(.plain)
                    .sagePlaceholder("https://github.com/user/vault.git", when: vm.remoteInput.isEmpty)
                    .padding(10)
                    .background(palette.inp, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
                SecureField("", text: $vm.tokenInput)
                    .textFieldStyle(.plain)
                    .sagePlaceholder(s.settings.gitTokenHint, when: vm.tokenInput.isEmpty)
                    .padding(10)
                    .background(palette.inp, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
                SageButton(s.settings.gitConnect) { vm.connectGit() }
            }
            .padding(28).frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(palette.bd2))
        }
    }

    private func gitConnected(settings settingsParam: SettingsStore) -> some View {
        @Bindable var settings = settingsParam
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SVGShape(SageIcons.githubMark, viewBox: CGSize(width: 16, height: 16)).fill(palette.tx)
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38).background(Color(hex: "#161B22"), in: RoundedRectangle(cornerRadius: Radius.md))
                VStack(alignment: .leading, spacing: 2) {
                    Text(gitDisplayURL(vm.gitInfo?.remoteURL ?? settings.gitRemote ?? "—")).font(.sage(13.5, .semibold)).foregroundStyle(palette.tx).lineLimit(1)
                    Text(gitSubtitle).font(.sage(12)).foregroundStyle(palette.tx3)
                }
                Spacer()
                if vm.gitSyncing {
                    HStack(spacing: 6) { SageSpinner(size: 12); Text(s.settings.syncing).font(.sage(12)).foregroundStyle(palette.tx2) }
                } else {
                    HStack(spacing: 6) { StatusDot(size: 7); Text(s.settings.synced).font(.sage(12)).foregroundStyle(palette.ac) }
                }
            }
            .padding(15).background(palette.bg1, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.bd, lineWidth: 1))
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Button { vm.syncNow() } label: {
                    HStack(spacing: 8) {
                        if vm.gitSyncing { SageSpinner(size: 13) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                        Text(s.settings.syncNow)
                    }
                    .font(.sage(13)).foregroundStyle(palette.tx)
                    .frame(maxWidth: .infinity).padding(11)
                    .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd, lineWidth: 1))
                }.buttonStyle(.plain)
                Button { vm.disconnectGit() } label: {
                    Text(s.settings.disconnect).font(.sage(13)).foregroundStyle(palette.error)
                        .padding(.vertical, 11).padding(.horizontal, 18)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.bottom, 22)

            settingRow(s.settings.autoSync, s.settings.autoSyncSub) { SageToggle(isOn: $settings.autoSync) }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.settings.syncFrequency).font(.sage(13.5, .medium)).foregroundStyle(palette.tx)
                    Text(s.settings.syncFrequencySub).font(.sage(12)).foregroundStyle(palette.tx3)
                }
                SageSegmented(
                    GitSyncFrequency.allCases.map { SegmentItem(tag: $0, label: freqLabel($0)) },
                    selection: $settings.gitFrequency,
                    accentSelected: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 15)
            if !vm.commits.isEmpty {
                Text(s.settings.recentCommits).sageType(.caption).foregroundStyle(palette.tx2).padding(.top, 8).padding(.bottom, 8)
                ForEach(vm.commits) { commit in
                    HStack(spacing: 10) {
                        Text(commit.shortHash).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(palette.ac)
                        Text(commit.message).font(.sage(12.5)).foregroundStyle(palette.tx).lineLimit(1)
                        Spacer()
                        Text(Formatting.relativeTime(commit.date)).font(.sage(11.5)).foregroundStyle(palette.tx3)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - About

    // MARK: - Обновления (OTA по воздуху, макет Section 8)

    private var updatesTab: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            tabHeader(s.settings.updates, s.settings.updatesSub)
            updateStatusRow
            updateActionArea
            settingRow(s.settings.autoUpdate, s.settings.autoUpdateSub) { SageToggle(isOn: $settings.autoUpdate) }
            settingRow(s.settings.checkUpdates, lastCheckText, divider: false) {
                Button { updaterVM.checkNow() } label: {
                    Text(s.settings.checkNow).font(.sage(12.5)).foregroundStyle(palette.tx2)
                        .padding(.vertical, 7).padding(.horizontal, 13)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).hoverHighlight(palette.bgh)
            }
        }
        .task { updaterVM.checkInBackground() }
    }

    private var updateStatusRow: some View {
        HStack(spacing: 14) {
            AppMark(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(CoreKit.appName) \(updaterVM.currentVersion)").font(.sage(15, .semibold)).foregroundStyle(palette.tx)
                Text(statusSubtitle).font(.sage(12)).foregroundStyle(palette.tx3)
            }
            Spacer()
            updateStatusTrailing
        }
        .padding(.bottom, 18)
    }

    @ViewBuilder private var updateStatusTrailing: some View {
        switch updaterVM.phase {
        case .checking, .downloading, .installing:
            SageSpinner(size: 16)
        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                Text(s.settings.upToDate).font(.sage(11.5, .semibold))
            }
            .foregroundStyle(palette.ac)
            .padding(.vertical, 5).padding(.horizontal, 11)
            .background(palette.acs, in: Capsule())
        default: EmptyView()
        }
    }

    @ViewBuilder private var updateActionArea: some View {
        switch updaterVM.phase {
        case let .available(r):
            updateBanner(icon: "arrow.down", tint: palette.ac,
                         title: "\(s.settings.updateAvailable) \(r.version)", subtitle: releaseMeta(r)) {
                updateActionButton(s.settings.updateNow) { updaterVM.update() }
            }
        case let .downloading(f):
            VStack(alignment: .leading, spacing: 9) {
                Text("\(s.settings.downloadingUpdate) \(updaterVM.pendingRelease?.version ?? "")…  \(Int(f * 100))%")
                    .font(.sage(13, .semibold)).foregroundStyle(palette.tx)
                LinearProgress(fraction: f)
            }
            .padding(15)
            .background(palette.bg2, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.bd, lineWidth: 1))
            .padding(.bottom, 22)
        case let .readyToInstall(r):
            updateBanner(icon: "checkmark", tint: palette.ac,
                         title: "\(CoreKit.appName) \(r.version) — \(s.settings.updateReady)", subtitle: s.settings.updatesSub) {
                updateActionButton(s.settings.restartNow) { updaterVM.restart() }
            }
        case let .failed(msg):
            updateBanner(icon: "exclamationmark.triangle", tint: palette.error,
                         title: s.settings.updateFailed, subtitle: msg) {
                updateActionButton(s.settings.retryUpdate) { updaterVM.checkNow() }
            }
        default: EmptyView()
        }
    }

    private func updateBanner<Action: View>(icon: String, tint: Color, title: String, subtitle: String,
                                            @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(palette.onAccent)
                .frame(width: 38, height: 38).background(tint, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sage(14, .semibold)).foregroundStyle(palette.tx)
                Text(subtitle).font(.sage(12)).foregroundStyle(palette.tx2).lineLimit(2)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(15)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.28), lineWidth: 1))
        .padding(.bottom, 22)
    }

    private func updateActionButton(_ title: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).font(.sage(12.5, .semibold)).foregroundStyle(palette.onAccent)
                .padding(.vertical, 8).padding(.horizontal, 15)
                .background(palette.ac, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusSubtitle: String {
        switch updaterVM.phase {
        case .idle, .upToDate: lastCheckText
        case .checking: s.settings.checkingUpdates
        case .available: s.settings.updateAvailable
        case .downloading: s.settings.downloadingUpdate
        case .installing: s.settings.installingUpdate
        case .readyToInstall: s.settings.updateReady
        case .failed: s.settings.updateFailed
        }
    }

    private var lastCheckText: String {
        guard let date = updaterVM.lastCheck else { return s.settings.lastChecked }
        let rel = Formatting.relativeOrJustNow(date, justNow: s.common.justNow,
                                               locale: Locale(identifier: locale.language.localeIdentifier))
        return "\(s.settings.lastChecked): \(rel)"
    }

    private func releaseMeta(_ r: UpdateRelease) -> String {
        let size = Formatting.fileSize(r.sizeBytes)
        return "\(size) · \(s.settings.youHaveVersion) \(updaterVM.currentVersion)"
    }

    private var aboutTab: some View {
        VStack(spacing: 0) {
            AppMark(size: 88).padding(.bottom, 18)
            Text("Sage").sageType(.h2).foregroundStyle(palette.tx).padding(.bottom, 4)
            Text(s.brandTagline).font(.sage(13.5)).foregroundStyle(palette.tx2).padding(.bottom, 4)
            Text("\(s.settings.version) \(CoreKit.appVersion) · macOS · Apple Silicon").font(.sage(12)).foregroundStyle(palette.tx3).padding(.bottom, 22)
            HStack(spacing: 8) {
                aboutChip("🔒 " + s.settings.chipLocal)
                aboutChip("⚡ " + s.settings.chipSilicon)
                aboutChip("📄 " + s.settings.chipMarkdown)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func aboutChip(_ text: String) -> some View {
        Text(text).font(.sage(12)).foregroundStyle(palette.tx2)
            .padding(.vertical, 6).padding(.horizontal, 13)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
    }

    // MARK: - Хелперы

    private func tabHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sageType(.h2).foregroundStyle(palette.tx)
            Text(subtitle).font(.sage(13)).foregroundStyle(palette.tx2)
        }
        .padding(.bottom, 26)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.sage(12, .semibold)).foregroundStyle(palette.tx2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
    }

    private func settingRow<Trailing: View>(_ title: String, _ subtitle: String, divider: Bool = true, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sage(13.5, .medium)).foregroundStyle(palette.tx)
                    Text(subtitle).font(.sage(12)).foregroundStyle(palette.tx3)
                }
                Spacer()
                trailing()
            }
            .padding(.vertical, 15)
            if divider { Rectangle().fill(palette.bd).frame(height: 1) }
        }
    }

    private func tabTitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: s.settings.general
        case .ai: s.settings.ai
        case .appearance: s.settings.appearance
        case .git: s.settings.git
        case .updates: s.settings.updates
        case .about: s.settings.about
        }
    }

    private func langCode(_ lang: AppLanguage) -> String {
        switch lang {
        case .ru: "RU"
        case .en: "EN"
        case .zh: "中"
        }
    }

    private func gitDisplayURL(_ raw: String) -> String {
        var str = raw
        if str.hasPrefix("git@") {
            str = String(str.dropFirst(4)).replacingOccurrences(of: ":", with: "/")
        }
        str = str.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        if str.hasSuffix(".git") { str = String(str.dropLast(4)) }
        return str.isEmpty ? "—" : str
    }

    private var gitSubtitle: String {
        let branch = vm.gitInfo?.branch ?? "main"
        var line = "\(s.settings.branch): \(branch)"
        if let date = vm.gitInfo?.lastSync {
            line += " · \(s.settings.lastSync) \(Formatting.relativeOrJustNow(date, justNow: s.common.justNow, locale: Locale(identifier: locale.language.localeIdentifier)))"
        }
        return line
    }

    private func freqLabel(_ freq: GitSyncFrequency) -> String {
        switch freq {
        case .onChange: s.settings.freqOnChange
        case .every5min: s.settings.freqEvery5
        case .hourly: s.settings.freqHourly
        case .manual: s.settings.freqManual
        }
    }
}
