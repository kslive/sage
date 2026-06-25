import CoreKit
import Foundation
import Localization
import SageTestSupport
import SettingsStore
import XCTest
@testable import OnboardingFeature

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var models: MockModelManaging!
    private var finish: FinishSpy!

    override func setUp() {
        super.setUp()
        models = MockModelManaging()
        finish = FinishSpy()
    }

    private func makeVM(language: AppLanguage = .ru) -> OnboardingViewModel {
        OnboardingViewModel(models: models, settings: makeSettings(), locale: makeLocale(language)) { [finish] in
            finish?.fire()
        }
    }

    /// Эталонные строки (LocaleManager.strings — публичный доступ к Strings).
    private func strings(_ language: AppLanguage = .ru) -> Strings { makeLocale(language).strings }

    // MARK: - Дефолты

    func testDefaults() {
        let vm = makeVM()
        XCTAssertEqual(vm.step, 0)
        XCTAssertEqual(vm.selectedModelID, ModelCatalog.defaultLLM)
        XCTAssertEqual(vm.selectedModelID, "qwen3-8b")
        XCTAssertEqual(vm.selectedWhisperID, ModelCatalog.defaultWhisper)
        XCTAssertEqual(vm.phase, .model)
        XCTAssertEqual(vm.fraction, 0)
        XCTAssertFalse(vm.failed)
        XCTAssertFalse(vm.verifying)
        XCTAssertNil(vm.folderURL)
        XCTAssertEqual(vm.speedText, "")
    }

    // MARK: - canAdvance

    func testCanAdvanceStep0() {
        let vm = makeVM(); vm.step = 0
        XCTAssertTrue(vm.canAdvance)
    }

    func testCanAdvanceStep1RequiresFolder() {
        let vm = makeVM(); vm.step = 1
        XCTAssertFalse(vm.canAdvance, "без папки нельзя продолжить со шага 1")
        vm.folderURL = URL(fileURLWithPath: "/tmp")
        XCTAssertTrue(vm.canAdvance)
    }

    func testCanAdvanceOtherSteps() {
        let vm = makeVM()
        for step in [2, 3, 4] { vm.step = step; XCTAssertTrue(vm.canAdvance) }
    }

    // MARK: - back()

    func testBackFromZeroStays() {
        let vm = makeVM(); vm.step = 0
        vm.back()
        XCTAssertEqual(vm.step, 0)
    }

    func testBackDecrements() {
        let vm = makeVM(); vm.step = 3
        vm.back(); XCTAssertEqual(vm.step, 2)
        vm.back(); XCTAssertEqual(vm.step, 1)
    }

    func testBackBlockedDuringDownload() {
        let vm = makeVM(); vm.step = 4
        vm.back()
        XCTAssertEqual(vm.step, 4, "со шага загрузки назад нельзя")
    }

    // MARK: - next()

    func testNextLinearAdvance() {
        let vm = makeVM()
        vm.step = 0; vm.next(); XCTAssertEqual(vm.step, 1)
        vm.step = 1; vm.next(); XCTAssertEqual(vm.step, 2)
        vm.step = 2; vm.next(); XCTAssertEqual(vm.step, 3)
    }

    func testNextStep3StartsDownload() async {
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.step = 3
        vm.next()
        XCTAssertEqual(vm.step, 4)
        XCTAssertNotNil(vm.downloadTask)
        await vm.downloadTask?.value
        XCTAssertEqual(vm.phase, .done)
    }

    func testNextStep4CallsFinish() {
        let vm = makeVM()
        vm.step = 4
        vm.next()
        XCTAssertEqual(finish.count, 1)
    }

    // MARK: - Выбор

    func testSelectModel() {
        let vm = makeVM()
        vm.selectModel("qwen3-4b")
        XCTAssertEqual(vm.selectedModelID, "qwen3-4b")
    }

    func testSelectWhisper() {
        let vm = makeVM()
        vm.selectWhisper("small")
        XCTAssertEqual(vm.selectedWhisperID, "small")
        vm.selectWhisper(nil)
        XCTAssertNil(vm.selectedWhisperID)
    }

    func testSetLanguage() {
        let locale = makeLocale(.ru)
        let vm = OnboardingViewModel(models: models, settings: makeSettings(), locale: locale, onFinish: {})
        XCTAssertEqual(vm.language, .ru)
        vm.setLanguage(.en)
        XCTAssertEqual(vm.language, .en)
        XCTAssertEqual(locale.language, .en)
    }

    // MARK: - folder

    func testFolderName() {
        let vm = makeVM()
        XCTAssertEqual(vm.folderName, "")
        XCTAssertFalse(vm.hasFolder)
        vm.folderURL = URL(fileURLWithPath: "/Users/x/Documents/Vault")
        XCTAssertEqual(vm.folderName, "Vault")
        XCTAssertTrue(vm.hasFolder)
    }

    // MARK: - downloadingModelName

    func testDownloadingModelName() {
        let vm = makeVM()
        vm.selectedModelID = "qwen3-8b"
        vm.selectedWhisperID = "base"
        vm.phase = .model
        XCTAssertEqual(vm.downloadingModelName, ModelCatalog.llm(id: "qwen3-8b")?.name)
        vm.phase = .whisper
        XCTAssertEqual(vm.downloadingModelName, ModelCatalog.whisper(id: "base")?.name)
        vm.phase = .done
        XCTAssertEqual(vm.downloadingModelName, ModelCatalog.whisper(id: "base")?.name)
    }

    func testDownloadingModelNameDoneNoWhisper() {
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.phase = .done
        XCTAssertEqual(vm.downloadingModelName, ModelCatalog.llm(id: vm.selectedModelID)?.name)
    }

    // MARK: - Загрузка

    func testDownloadSuccessBoth() async {
        models.llmStates = DownloadStates.success
        models.whisperStates = DownloadStates.success
        let vm = makeVM()
        vm.selectedWhisperID = "base"
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertEqual(vm.phase, .done)
        XCTAssertEqual(vm.fraction, 1)
        XCTAssertFalse(vm.failed)
        XCTAssertEqual(models.llmRequested, [vm.selectedModelID])
        XCTAssertEqual(models.whisperRequested, ["base"])
    }

    func testDownloadSkipsWhisperWhenNil() async {
        models.llmStates = DownloadStates.success
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertEqual(vm.phase, .done)
        XCTAssertTrue(models.whisperRequested.isEmpty, "whisper не должен качаться, если не выбран")
    }

    func testDownloadLLMFailureStops() async {
        models.llmStates = DownloadStates.failure
        let vm = makeVM()
        vm.selectedWhisperID = "base"
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertTrue(vm.failed)
        XCTAssertEqual(vm.phase, .model, "при провале LLM фаза не уходит в whisper")
        XCTAssertTrue(models.whisperRequested.isEmpty, "whisper не качается после провала LLM")
    }

    func testDownloadWhisperFailure() async {
        models.llmStates = DownloadStates.success
        models.whisperStates = DownloadStates.failure
        let vm = makeVM()
        vm.selectedWhisperID = "base"
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertTrue(vm.failed)
        XCTAssertEqual(vm.phase, .whisper)
        XCTAssertEqual(models.whisperRequested, ["base"])
    }

    func testVerifyingSetsFlag() async {
        models.llmStates = [.verifying]
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertTrue(vm.verifying)
    }

    func testSpeedTextWithSpeed() async {
        models.llmStates = [DownloadStates.progress(done: 10, total: 100, speed: 50)]
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertFalse(vm.speedText.isEmpty)
        XCTAssertTrue(vm.speedText.contains("·"), "при скорости > 0 показываем скорость через ·")
    }

    func testSpeedTextWithoutSpeed() async {
        models.llmStates = [DownloadStates.progress(done: 10, total: 100, speed: 0)]
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertFalse(vm.speedText.isEmpty)
        XCTAssertFalse(vm.speedText.contains("·"), "при скорости 0 — только размеры, без ·")
    }

    func testRetryAfterFailureSucceeds() async {
        models.llmStates = DownloadStates.failure
        let vm = makeVM()
        vm.selectedWhisperID = nil
        vm.startDownloads()
        await vm.downloadTask?.value
        XCTAssertTrue(vm.failed)

        models.llmStates = DownloadStates.success
        vm.retry()
        XCTAssertFalse(vm.failed, "retry сбрасывает флаг ошибки")
        await vm.downloadTask?.value
        XCTAssertEqual(vm.phase, .done)
        XCTAssertFalse(vm.failed)
    }

    // MARK: - finish()

    func testFinishPersistsAndCallsBack() {
        let suite = UserDefaults(suiteName: "test.finish." + UUID().uuidString)!
        let settings = SettingsStore(defaults: suite)
        settings.onboardingComplete = false
        let vm = OnboardingViewModel(models: models, settings: settings, locale: makeLocale()) { [finish] in finish?.fire() }
        vm.selectModel("qwen3-4b")
        vm.selectWhisper("small")
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        vm.folderURL = tmp

        vm.finish()

        XCTAssertTrue(settings.onboardingComplete)
        XCTAssertEqual(settings.activeLLMId, "qwen3-4b")
        XCTAssertEqual(settings.activeWhisperId, "small")
        XCTAssertFalse(settings.vaultPath.isEmpty)
        XCTAssertNotNil(settings.resolveVaultURL())
        XCTAssertEqual(finish.count, 1)
    }

    func testFinishWithoutFolder() {
        let suite = UserDefaults(suiteName: "test.finish2." + UUID().uuidString)!
        let settings = SettingsStore(defaults: suite)
        let vm = OnboardingViewModel(models: models, settings: settings, locale: makeLocale()) { [finish] in finish?.fire() }
        vm.folderURL = nil
        vm.selectWhisper(nil)

        vm.finish()

        XCTAssertTrue(settings.onboardingComplete)
        XCTAssertNil(settings.activeWhisperId)
        XCTAssertTrue(settings.vaultPath.isEmpty, "без папки vault не трогается")
        XCTAssertEqual(finish.count, 1)
    }

    // MARK: - Тексты (перенесённые из вью хелперы)

    func testModelDesc() {
        let vm = makeVM(language: .ru)
        XCTAssertEqual(vm.modelDesc("qwen3-1.7b"), strings().models.descSmall)
        XCTAssertEqual(vm.modelDesc("qwen3-4b"), strings().models.descMid)
        XCTAssertEqual(vm.modelDesc("qwen3-8b"), strings().models.descLarge)
        XCTAssertEqual(vm.modelDesc("unknown"), "")
    }

    func testModelRAM() {
        let vm = makeVM(language: .ru)
        XCTAssertEqual(vm.modelRAM("qwen3-1.7b"), strings().models.ramSmall)
        XCTAssertEqual(vm.modelRAM("qwen3-4b"), strings().models.ramMid)
        XCTAssertEqual(vm.modelRAM("qwen3-8b"), strings().models.ramLarge)
        XCTAssertEqual(vm.modelRAM("unknown"), "")
    }

    func testWhisperDesc() {
        let vm = makeVM(language: .ru)
        XCTAssertEqual(vm.whisperDesc("base"), strings().models.whisperBaseDesc)
        XCTAssertEqual(vm.whisperDesc("small"), strings().models.whisperSmallDesc)
        XCTAssertEqual(vm.whisperDesc("tiny"), strings().models.whisperTinyDesc)
        XCTAssertEqual(vm.whisperDesc("large-v3-turbo"), strings().models.whisperTurboDesc)
        XCTAssertEqual(vm.whisperDesc("unknown"), "")
    }

    func testLangSubtitle() {
        let vm = makeVM()
        XCTAssertEqual(vm.langSubtitle(.ru), "Russian")
        XCTAssertEqual(vm.langSubtitle(.en), "Английский")
        XCTAssertEqual(vm.langSubtitle(.zh), "Китайский")
    }

    func testStageLine() {
        let vm = makeVM(language: .ru)
        vm.selectedWhisperID = nil
        XCTAssertEqual(vm.stageLine, strings().ob.stageOnlyModel)
        vm.selectedWhisperID = "base"
        vm.phase = .model
        XCTAssertEqual(vm.stageLine, strings().ob.stageModel)
        vm.phase = .whisper
        XCTAssertEqual(vm.stageLine, strings().ob.stageWhisper)
        vm.phase = .done
        XCTAssertEqual(vm.stageLine, strings().ob.stageWhisper)
    }

    func testStatusText() {
        let vm = makeVM(language: .ru)
        vm.failed = true
        XCTAssertEqual(vm.statusText, strings().ob.dlErrorMsg)
        vm.failed = false; vm.verifying = true
        XCTAssertEqual(vm.statusText, strings().ob.verifying)
        vm.verifying = false; vm.phase = .done
        XCTAssertEqual(vm.statusText, strings().ob.dlDone)
        vm.phase = .model
        XCTAssertEqual(vm.statusText, strings().ob.downloading)
    }

    func testNavTitle() {
        let vm = makeVM(language: .ru)
        vm.step = 3; XCTAssertEqual(vm.navTitle, strings().ob.downloadContinue)
        vm.step = 4; XCTAssertEqual(vm.navTitle, strings().ob.openSage)
        vm.step = 0; XCTAssertEqual(vm.navTitle, strings().ob.continueAction)
    }
}
