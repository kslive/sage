import CoreKit
import Foundation
import XCTest
@testable import SettingsStore

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func suite() -> UserDefaults { UserDefaults(suiteName: "ss." + UUID().uuidString)! }

    func testDefaultsFreshSuite() {
        let s = SettingsStore(defaults: suite())
        XCTAssertFalse(s.onboardingComplete)
        XCTAssertEqual(s.activeLLMId, ModelCatalog.defaultLLM)
        XCTAssertEqual(s.activeWhisperId, ModelCatalog.defaultWhisper)
        XCTAssertEqual(s.temperature, 0.7, accuracy: 0.0001)
        XCTAssertTrue(s.vaultPath.isEmpty)
    }

    func testPersistenceRoundtrip() {
        let d = suite()
        let s1 = SettingsStore(defaults: d)
        s1.onboardingComplete = true
        s1.activeLLMId = "qwen3-4b"
        s1.activeWhisperId = "small"
        s1.temperature = 0.42
        s1.vaultPath = "/tmp/vault"
        let s2 = SettingsStore(defaults: d)
        XCTAssertTrue(s2.onboardingComplete)
        XCTAssertEqual(s2.activeLLMId, "qwen3-4b")
        XCTAssertEqual(s2.activeWhisperId, "small")
        XCTAssertEqual(s2.temperature, 0.42, accuracy: 0.0001)
        XCTAssertEqual(s2.vaultPath, "/tmp/vault")
    }

    func testActiveLLMLookup() {
        let s = SettingsStore(defaults: suite())
        s.activeLLMId = "qwen3-8b"
        XCTAssertEqual(s.activeLLM?.name, "Qwen3 8B")
        s.activeWhisperId = "base"
        XCTAssertEqual(s.activeWhisper?.name, "Whisper Base")
    }

    func testResolveVaultURLFromPath() {
        let s = SettingsStore(defaults: suite())
        XCTAssertNil(s.resolveVaultURL())
        s.vaultPath = "/tmp/myvault"
        XCTAssertEqual(s.resolveVaultURL()?.path, "/tmp/myvault")
    }

    func testSetVaultStoresPath() {
        let s = SettingsStore(defaults: suite())
        let dir = FileManager.default.temporaryDirectory
        s.setVault(url: dir)
        XCTAssertEqual(s.vaultPath, dir.path)
        XCTAssertNotNil(s.resolveVaultURL())
    }

    func testTransientFieldsNotPersisted() {
        let d = suite()
        let s1 = SettingsStore(defaults: d)
        s1.currentNotePath = "/x/note.md"
        s1.currentSelection = "selected"
        let s2 = SettingsStore(defaults: d)
        XCTAssertNil(s2.currentNotePath)
        XCTAssertNil(s2.currentSelection)
    }

    func testSidebarSortDefaultAndPersistence() {
        let d = suite()
        let s1 = SettingsStore(defaults: d)
        XCTAssertEqual(s1.sidebarSort, .name)            // дефолт
        s1.sidebarSort = .modified
        let s2 = SettingsStore(defaults: d)
        XCTAssertEqual(s2.sidebarSort, .modified)         // персист
    }

    func testUpdateFieldsDefaultsAndPersistence() {
        let d = suite()
        let s1 = SettingsStore(defaults: d)
        // дефолты OTA
        XCTAssertTrue(s1.autoUpdate)
        XCTAssertNil(s1.lastUpdateCheck)
        XCTAssertNil(s1.pendingUpdateVersion)
        XCTAssertNil(s1.pendingUpdatePath)
        // персист
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        s1.autoUpdate = false
        s1.lastUpdateCheck = date
        s1.pendingUpdateVersion = "1.2.3"
        s1.pendingUpdatePath = "/tmp/staged/Sage.app"
        let s2 = SettingsStore(defaults: d)
        XCTAssertFalse(s2.autoUpdate)
        XCTAssertEqual(s2.lastUpdateCheck, date)
        XCTAssertEqual(s2.pendingUpdateVersion, "1.2.3")
        XCTAssertEqual(s2.pendingUpdatePath, "/tmp/staged/Sage.app")
    }
}
