import AppKit
import CoreKit
import Localization
import Observation
import SettingsStore
import SwiftUI

@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Phase { case model, whisper, done }

    public var step = 0
    public var folderURL: URL?
    public var selectedModelID = ModelCatalog.defaultLLM
    public var selectedWhisperID: String? = ModelCatalog.defaultWhisper

    public var phase: Phase = .model
    public var fraction: Double = 0
    public var speedText = ""
    public var failed = false
    public var verifying = false

    private let models: ModelManaging
    private let settings: SettingsStore
    private let locale: LocaleManager
    private let onFinish: () -> Void
    var downloadTask: Task<Void, Never>?

    public init(models: ModelManaging, settings: SettingsStore, locale: LocaleManager, onFinish: @escaping () -> Void) {
        self.models = models
        self.settings = settings
        self.locale = locale
        self.onFinish = onFinish
    }

    public var language: AppLanguage { locale.language }
    public var folderName: String { folderURL?.lastPathComponent ?? "" }
    public var hasFolder: Bool { folderURL != nil }

    public func setLanguage(_ lang: AppLanguage) { locale.setLanguage(lang) }
    public func selectModel(_ id: String) { selectedModelID = id }
    public func selectWhisper(_ id: String?) { selectedWhisperID = id }

    // MARK: - Навигация

    public var canAdvance: Bool {
        switch step {
        case 1: hasFolder
        default: true
        }
    }

    public func back() { if step > 0, step < 4 { step -= 1 } }

    public func next() {
        switch step {
        case 0, 1, 2: step += 1
        case 3:
            step = 4
            startDownloads()
        case 4:
            finish()
        default: break
        }
    }

    public func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = locale.strings.ob.chooseFolder
        if panel.runModal() == .OK, let url = panel.url {
            folderURL = url
        }
    }

    // MARK: - Загрузка

    public func startDownloads() {
        failed = false
        fraction = 0
        verifying = false
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            guard let self else { return }
            phase = .model
            if let spec = ModelCatalog.llm(id: selectedModelID) {
                let ok = await runStream(models.downloadLLM(spec))
                guard ok else { return }
            }
            if let wid = selectedWhisperID, let wspec = ModelCatalog.whisper(id: wid) {
                phase = .whisper
                fraction = 0
                let ok = await runStream(models.downloadWhisper(wspec))
                guard ok else { return }
            }
            phase = .done
            fraction = 1
        }
    }

    private func runStream(_ stream: AsyncStream<DownloadState>) async -> Bool {
        for await state in stream {
            switch state {
            case let .downloading(progress):
                verifying = false
                fraction = progress.fraction
                let sizes = Formatting.progress(done: progress.downloadedBytes, total: progress.totalBytes)
                speedText = progress.speedBytesPerSec > 0
                    ? sizes + " · " + Formatting.speed(bytesPerSec: progress.speedBytesPerSec, unit: locale.strings.ob.speedUnit)
                    : sizes
            case .verifying:
                verifying = true
            case .installed:
                verifying = false
                fraction = 1
                return true
            case .failed:
                failed = true
                return false
            case .notInstalled:
                break
            }
        }
        return !failed
    }

    public func retry() { startDownloads() }

    public func finish() {
        if let url = folderURL {
            _ = url.startAccessingSecurityScopedResource()
            settings.setVault(url: url)
        }
        settings.activeLLMId = selectedModelID
        settings.activeWhisperId = selectedWhisperID
        settings.onboardingComplete = true
        onFinish()
    }

    // MARK: - Производные для UI

    public var downloadingModelName: String {
        switch phase {
        case .model: ModelCatalog.llm(id: selectedModelID)?.name ?? ""
        case .whisper: selectedWhisperID.flatMap(ModelCatalog.whisper(id:))?.name ?? ""
        case .done:
            selectedWhisperID.flatMap(ModelCatalog.whisper(id:))?.name
                ?? ModelCatalog.llm(id: selectedModelID)?.name ?? ""
        }
    }

    // MARK: - Тексты для UI (перенесены из вью ради тестируемости; логика неизменна)

    private var s: Strings { locale.strings }

    public var stageLine: String {
        if selectedWhisperID == nil { return s.ob.stageOnlyModel }
        switch phase {
        case .model: return s.ob.stageModel
        case .whisper, .done: return s.ob.stageWhisper
        }
    }

    public var statusText: String {
        if failed { return s.ob.dlErrorMsg }
        if verifying { return s.ob.verifying }
        if phase == .done { return s.ob.dlDone }
        return s.ob.downloading
    }

    public var navTitle: String {
        switch step {
        case 3: s.ob.downloadContinue
        case 4: s.ob.openSage
        default: s.ob.continueAction
        }
    }

    public func modelDesc(_ id: String) -> String {
        switch id {
        case "qwen3-1.7b": s.models.descSmall
        case "qwen3-4b": s.models.descMid
        case "qwen3-8b": s.models.descLarge
        default: ""
        }
    }

    public func modelRAM(_ id: String) -> String {
        switch id {
        case "qwen3-1.7b": s.models.ramSmall
        case "qwen3-4b": s.models.ramMid
        case "qwen3-8b": s.models.ramLarge
        default: ""
        }
    }

    public func whisperDesc(_ id: String) -> String {
        switch id {
        case "base": s.models.whisperBaseDesc
        case "small": s.models.whisperSmallDesc
        case "tiny": s.models.whisperTinyDesc
        case "large-v3-turbo": s.models.whisperTurboDesc
        default: ""
        }
    }

    /// Подпись языка под названием — статично по макету (имя «на другом языке»).
    public func langSubtitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .ru: "Russian"
        case .en: "Английский"
        case .zh: "Китайский"
        }
    }
}
