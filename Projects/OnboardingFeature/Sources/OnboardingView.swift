import CoreKit
import DesignSystem
import Localization
import SettingsStore
import SwiftUI

public struct OnboardingView: View {
    @State private var vm: OnboardingViewModel
    @State private var folderHover = false
    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale

    public init(models: ModelManaging, settings: SettingsStore, locale: LocaleManager, onFinish: @escaping () -> Void) {
        _vm = State(wrappedValue: OnboardingViewModel(models: models, settings: settings, locale: locale, onFinish: onFinish))
    }

    private var s: Strings { locale.strings }

    public var body: some View {
        ZStack {
            OnboardingBackground()

            GeometryReader { geo in
                ScrollView {
                    VStack {
                        progressDots.padding(.top, 30)
                        Spacer(minLength: 28)
                        card
                            .frame(width: 520)
                            .id(vm.step)
                            .transition(.opacity)
                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(SageMotion.fade, value: vm.step)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< 5, id: \.self) { i in
                Capsule()
                    .fill(i <= vm.step ? palette.ac : palette.bd2)
                    .frame(width: i == vm.step ? 22 : 5, height: 5)
                    .animation(SageMotion.smooth, value: vm.step)
            }
        }
    }

    @ViewBuilder private var card: some View {
        VStack(spacing: 0) {
            switch vm.step {
            case 0: languageStep
            case 1: folderStep
            case 2: modelStep
            case 3: whisperStep
            default: downloadStep
            }
            navButtons
        }
    }

    // MARK: - Шаг 0: язык

    private var languageStep: some View {
        VStack(spacing: 0) {
            AppMark(size: 74).padding(.bottom, Spacing.lg)
            Text(s.ob.langTitle)
                .font(.sage(27, .bold)).tracking(-0.5)
                .foregroundStyle(palette.tx)
                .multilineTextAlignment(.center).padding(.bottom, Spacing.xs)
            Text(s.ob.langSub).font(.sage(14)).foregroundStyle(palette.tx2)
                .multilineTextAlignment(.center).padding(.bottom, Spacing.xl)
            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { lang in
                    optionRow(selected: vm.language == lang) { vm.setLanguage(lang) } content: {
                        Text(lang.flag).font(.sage(24)).frame(width: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lang.nativeName).sageType(.uiMedium).foregroundStyle(palette.tx)
                            Text(vm.langSubtitle(lang)).font(.sage(12)).foregroundStyle(palette.tx2)
                        }
                        Spacer()
                        radio(selected: vm.language == lang)
                    }
                }
            }
        }
    }

    // MARK: - Шаг 1: папка

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel(s.ob.stepFolder)
            Text(s.ob.folderTitle).sageType(.h1).foregroundStyle(palette.tx).padding(.bottom, Spacing.xs)
            Text(s.ob.folderSub).font(.sage(14)).foregroundStyle(palette.tx2).lineSpacing(2).padding(.bottom, 22)
            Button(action: vm.pickFolder) {
                VStack(spacing: 10) {
                    Text("📁").font(.sage(30))
                    if vm.hasFolder {
                        Text(vm.folderName).sageType(.uiMedium).foregroundStyle(palette.ac)
                        Text(s.ob.folderPicked).font(.sage(12)).foregroundStyle(palette.tx2)
                    } else {
                        Text(s.ob.chooseFolder).sageType(.uiMedium).foregroundStyle(palette.tx)
                        Text(s.ob.folderHint).font(.sage(12)).foregroundStyle(palette.tx2)
                    }
                }
                .frame(maxWidth: .infinity).padding(30)
                .background((folderHover ? palette.acs : palette.bg1), in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .foregroundStyle(folderHover ? palette.ac : palette.bd2)
                )
            }
            .buttonStyle(.plain)
            .onHover { folderHover = $0 }
            HStack(spacing: 8) {
                Text("🔒").foregroundStyle(palette.ac)
                Text(s.ob.privacyNote).font(.sage(12.5)).foregroundStyle(palette.tx2)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bg1, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd, lineWidth: 1))
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Шаг 2: модель

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel(s.ob.stepModel)
            Text(s.ob.modelTitle).sageType(.h1).foregroundStyle(palette.tx).padding(.bottom, Spacing.xs)
            Text(s.ob.modelSub).font(.sage(14)).foregroundStyle(palette.tx2).padding(.bottom, Spacing.lg)
            VStack(spacing: 9) {
                ForEach(ModelCatalog.llms) { spec in
                    optionRow(selected: vm.selectedModelID == spec.id) { vm.selectModel(spec.id) } content: {
                        modelIcon(spec.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(spec.name).font(.sage(14, .semibold)).foregroundStyle(palette.tx)
                                if spec.recommended { SageBadge(s.ob.recommended) }
                            }
                            Text(vm.modelDesc(spec.id)).font(.sage(12)).foregroundStyle(palette.tx2)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Formatting.fileSize(spec.sizeBytes)).font(.sage(12.5, .semibold)).foregroundStyle(palette.tx)
                            Text(vm.modelRAM(spec.id)).font(.sage(11)).foregroundStyle(palette.tx3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Шаг 3: whisper

    private var whisperStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel(s.ob.stepWhisper)
            Text(s.ob.whisperTitle).sageType(.h1).foregroundStyle(palette.tx).padding(.bottom, Spacing.xs)
            Text(s.ob.whisperSub).font(.sage(14)).foregroundStyle(palette.tx2).padding(.bottom, Spacing.lg)
            VStack(spacing: 9) {
                ForEach(ModelCatalog.whispers) { spec in
                    optionRow(selected: vm.selectedWhisperID == spec.id) { vm.selectWhisper(spec.id) } content: {
                        modelIcon(spec.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(spec.name).font(.sage(14, .semibold)).foregroundStyle(palette.tx)
                                if spec.recommended { SageBadge(s.ob.recommended) }
                            }
                            Text(vm.whisperDesc(spec.id)).font(.sage(12)).foregroundStyle(palette.tx2)
                        }
                        Spacer(minLength: 6)
                        Text(Formatting.fileSize(spec.sizeBytes)).font(.sage(12.5, .semibold)).foregroundStyle(palette.tx2)
                    }
                }
                optionRow(selected: vm.selectedWhisperID == nil) { vm.selectWhisper(nil) } content: {
                    modelIcon("⊘")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.models.whisperNone).font(.sage(14, .semibold)).foregroundStyle(palette.tx)
                        Text(s.models.whisperNoneDesc).font(.sage(12)).foregroundStyle(palette.tx2)
                    }
                    Spacer(minLength: 6)
                    Text("—").foregroundStyle(palette.tx3)
                }
            }
        }
    }

    // MARK: - Шаг 4: загрузка / готово

    @ViewBuilder private var downloadStep: some View {
        VStack(spacing: 0) {
            stepLabel(s.ob.stepDownload, centered: true)
            CircularProgress(fraction: vm.fraction, showError: vm.failed).padding(.bottom, Spacing.md)
            Text(vm.downloadingModelName).sageType(.h2).foregroundStyle(palette.tx).padding(.bottom, 6)
            if !vm.failed {
                Text(vm.statusText).font(.sage(13.5, .medium)).foregroundStyle(palette.ac)
            }
            Text(vm.stageLine).font(.sage(12)).foregroundStyle(palette.tx3).padding(.top, 4)
            if !vm.speedText.isEmpty, !vm.failed, vm.phase != .done {
                Text(vm.speedText).font(.sage(12)).foregroundStyle(palette.tx3).padding(.top, 2)
            }
            if vm.failed {
                Text(s.ob.dlErrorMsg)
                    .font(.sage(12.5)).foregroundStyle(Color(hex: "#FF8A8A"))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "#EB5757").opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color(hex: "#EB5757").opacity(0.3), lineWidth: 1))
                    .padding(.top, 18)
                SageButton(s.ob.retry, fullWidth: true, action: vm.retry).padding(.top, 14)
            }
            if vm.phase == .done {
                ZStack {
                    Circle().fill(palette.acs).frame(width: 70, height: 70)
                    Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.ac)
                }
                .padding(.top, Spacing.xl).padding(.bottom, Spacing.md)
                Text(s.ob.readyTitle).sageType(.h1).foregroundStyle(palette.tx).padding(.bottom, Spacing.xs)
                Text(s.ob.readySub).sageType(.body).foregroundStyle(palette.tx2)
                    .multilineTextAlignment(.center).padding(.bottom, Spacing.lg)
                HStack(spacing: 8) {
                    readyChip("📂", vm.folderName.isEmpty ? "~/Documents" : vm.folderName)
                    readyChip("🦙", ModelCatalog.llm(id: vm.selectedModelID)?.name ?? "")
                    readyChip("🌐", locale.language.nativeName)
                }
            }
        }
    }

    // MARK: - Навигация

    @ViewBuilder private var navButtons: some View {
        let showNav = vm.step != 4 || vm.phase == .done
        if showNav {
            HStack(spacing: 10) {
                if vm.step >= 1, vm.step <= 3 {
                    SageButton(s.common.back, kind: .secondary, action: vm.back)
                }
                SageButton(vm.navTitle, fullWidth: true) { withAnimation(SageMotion.fade) { vm.next() } }
                    .disabled(!vm.canAdvance)
                    .opacity(vm.canAdvance ? 1 : 0.5)
            }
            .padding(.top, Spacing.xl)
        }
    }

    // MARK: - Хелперы

    private func stepLabel(_ text: String, centered: Bool = false) -> some View {
        Text(text.uppercased())
            .font(.sage(12, .semibold))
            .tracking(0.5)
            .foregroundStyle(palette.ac)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.bottom, centered ? Spacing.md : 10)
    }

    private func optionRow<Content: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 13) { content() }
                .padding(.vertical, 13).padding(.horizontal, 15)
                .frame(maxWidth: .infinity)
                .background(selected ? palette.acs : palette.bg1, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(selected ? palette.ac : palette.bd, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func modelIcon(_ emoji: String) -> some View {
        Text(emoji).font(.sage(17))
            .frame(width: 38, height: 38)
            .background(palette.bg3, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func radio(selected: Bool) -> some View {
        Circle().strokeBorder(selected ? palette.ac : palette.bd2, lineWidth: 1.5)
            .frame(width: 18, height: 18)
            .overlay(Circle().fill(selected ? palette.ac : .clear).frame(width: 9, height: 9))
    }

    private func readyChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(icon).font(.sage(12))
            Text(text).font(.sage(12.5)).foregroundStyle(palette.tx).lineLimit(1)
        }
        .padding(.vertical, 7).padding(.horizontal, 13)
        .background(palette.bg1, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd, lineWidth: 1))
    }

}
