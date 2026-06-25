import CoreKit
import Foundation
import Localization
import SageTestSupport
import SettingsStore
import UpdateService
import XCTest
@testable import SettingsFeature

@MainActor
final class UpdaterViewModelTests: XCTestCase {
    // MARK: - окружение

    private func makeEnv() -> (vm: UpdaterViewModel, mock: MockUpdateServicing, settings: SettingsStore, s: Strings) {
        let mock = MockUpdateServicing()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "ut-updater-\(UUID().uuidString)")!)
        let locale = LocaleManager()
        let vm = UpdaterViewModel(updater: mock, settings: settings, locale: locale)
        return (vm, mock, settings, locale.strings)
    }

    private func release(_ v: String, prerelease: Bool = false) -> UpdateRelease {
        UpdateRelease(version: v, notes: "", downloadURL: URL(string: "https://x/\(v).zip")!,
                      sha256: nil, sha256AssetURL: nil, sizeBytes: 1, publishedAt: nil, isPrerelease: prerelease)
    }

    private func wait(_ cond: @escaping () -> Bool, _ timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    private func isReady(_ p: UpdaterPhase) -> Bool { if case .readyToInstall = p { return true }; return false }
    private func isAvailable(_ p: UpdaterPhase) -> Bool { if case .available = p { return true }; return false }
    private func isFailed(_ p: UpdaterPhase) -> Bool { if case .failed = p { return true }; return false }

    // MARK: - check

    func testCheckNowAvailable() async {
        let (vm, mock, settings, _) = makeEnv()
        mock.releaseToReturn = release("2.0.0")
        vm.checkNow()
        await wait { self.isAvailable(vm.phase) }
        guard case let .available(r) = vm.phase else { return XCTFail("ожидали .available") }
        XCTAssertEqual(r.version, "2.0.0")
        XCTAssertNotNil(settings.lastUpdateCheck)
    }

    func testCheckNowUpToDate() async {
        let (vm, mock, _, _) = makeEnv()
        mock.releaseToReturn = nil
        vm.checkNow()
        await wait { if case .upToDate = vm.phase { return true }; return false }
        if case .upToDate = vm.phase {} else { XCTFail("ожидали .upToDate") }
    }

    func testCheckErrorLocalized() async {
        let (vm, mock, _, s) = makeEnv()
        mock.checkError = UpdateError.badResponse
        vm.checkNow()
        await wait { self.isFailed(vm.phase) }
        XCTAssertEqual(vm.phase, .failed(s.settings.updateErrNetwork))
    }

    func testGenericErrorMapsToNetwork() async {
        let (vm, mock, _, s) = makeEnv()
        mock.checkError = URLError(.timedOut)
        vm.checkNow()
        await wait { self.isFailed(vm.phase) }
        XCTAssertEqual(vm.phase, .failed(s.settings.updateErrNetwork))
    }

    // MARK: - download → stage → readyToInstall

    func testFullDownloadFlowPersistsPending() async {
        let (vm, mock, settings, _) = makeEnv()
        let zip = URL(fileURLWithPath: "/tmp/Sage-2.0.0.zip")
        let staged = URL(fileURLWithPath: "/tmp/sage-staged/Sage.app")
        mock.releaseToReturn = release("2.0.0")
        mock.downloadEvents = [.progress(UpdateProgress(received: 50, total: 100)), .finished(zip)]
        mock.stagedAppToReturn = staged
        settings.autoUpdate = false
        vm.checkNow()
        await wait { self.isAvailable(vm.phase) }
        vm.update()
        await wait { self.isReady(vm.phase) }
        guard case let .readyToInstall(r) = vm.phase else { return XCTFail("ожидали .readyToInstall") }
        XCTAssertEqual(r.version, "2.0.0")
        XCTAssertEqual(settings.pendingUpdateVersion, "2.0.0")
        XCTAssertEqual(settings.pendingUpdatePath, staged.path)
        XCTAssertEqual(mock.stagedZip, zip)
    }

    func testDownloadIncomplete() async {
        let (vm, mock, _, s) = makeEnv()
        mock.releaseToReturn = release("2.0.0")
        mock.downloadEvents = [.progress(UpdateProgress(received: 50, total: 100))] // нет .finished
        vm.checkNow()
        await wait { self.isAvailable(vm.phase) }
        vm.update()
        await wait { self.isFailed(vm.phase) }
        XCTAssertEqual(vm.phase, .failed(s.settings.downloadIncomplete))
    }

    func testDownloadChecksumErrorLocalized() async {
        let (vm, mock, _, s) = makeEnv()
        mock.releaseToReturn = release("2.0.0")
        mock.downloadError = UpdateError.checksumMismatch
        vm.checkNow()
        await wait { self.isAvailable(vm.phase) }
        vm.update()
        await wait { self.isFailed(vm.phase) }
        XCTAssertEqual(vm.phase, .failed(s.settings.updateErrChecksum))
    }

    // MARK: - троттл

    func testThrottleSkipsRecent() async {
        let (vm, mock, settings, _) = makeEnv()
        settings.lastUpdateCheck = Date()
        vm.checkInBackground()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(mock.checkCount, 0, "свежая проверка → фоновую пропускаем")
    }

    func testCheckNowIgnoresThrottle() async {
        let (vm, mock, settings, _) = makeEnv()
        settings.lastUpdateCheck = Date()
        vm.checkNow()
        await wait { mock.checkCount == 1 }
        XCTAssertEqual(mock.checkCount, 1)
    }

    func testThrottleAllowsOld() async {
        let (vm, mock, settings, _) = makeEnv()
        settings.lastUpdateCheck = Date().addingTimeInterval(-7 * 3600)
        vm.checkInBackground()
        await wait { mock.checkCount == 1 }
        XCTAssertEqual(mock.checkCount, 1)
    }

    // MARK: - short-circuit «уже подготовлено»

    func testAlreadyStagedSkipsDownload() async throws {
        let (vm, mock, settings, _) = makeEnv()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).app")
        try Data().write(to: tmp) // существующий «бандл» (для FileManager.fileExists)
        defer { try? FileManager.default.removeItem(at: tmp) }
        settings.pendingUpdateVersion = "1.5.0"
        settings.pendingUpdatePath = tmp.path
        settings.autoUpdate = true
        mock.releaseToReturn = release("1.5.0")
        vm.checkNow()
        await wait { self.isReady(vm.phase) }
        XCTAssertNil(mock.stagedZip, "уже подготовлено → не скачиваем заново")
    }

    // MARK: - restart

    func testPrepareUpdateForRestart() {
        let (vm, mock, settings, _) = makeEnv()
        let staged = "/tmp/sage-staged/Sage.app"
        settings.pendingUpdateVersion = "2.0.0"
        settings.pendingUpdatePath = staged
        let ok = vm.prepareUpdateForRestart()
        XCTAssertTrue(ok)
        XCTAssertNil(settings.pendingUpdateVersion)
        XCTAssertNil(settings.pendingUpdatePath)
        XCTAssertEqual(mock.appliedStaged?.path, staged)
        XCTAssertEqual(mock.appliedRelaunch, true)
    }

    func testPrepareUpdateForRestartNothingStaged() {
        let (vm, _, _, _) = makeEnv()
        XCTAssertFalse(vm.prepareUpdateForRestart())
    }
}
