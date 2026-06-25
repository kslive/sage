import Foundation
import XCTest
@testable import CoreKit

final class UpdateLogicTests: XCTestCase {
    func testCompareVersions() {
        XCTAssertEqual(UpdateLogic.compareVersions("1.0.0", "1.5.0"), -1)
        XCTAssertEqual(UpdateLogic.compareVersions("1.5.0", "1.5.0"), 0)
        XCTAssertEqual(UpdateLogic.compareVersions("v2.0", "1.9.9"), 1)   // ведущий v + разная длина
        XCTAssertEqual(UpdateLogic.compareVersions("1.10.0", "1.9.0"), 1) // числовое, не лексикографическое
        XCTAssertEqual(UpdateLogic.compareVersions("1.5.0-beta.1", "1.5.0"), 0) // пререлизный суффикс игнор
        XCTAssertTrue(UpdateLogic.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertFalse(UpdateLogic.isNewer("1.0.0", than: "1.0.0"))
    }

    private func release(_ v: String, prerelease: Bool = false) -> UpdateRelease {
        UpdateRelease(version: v, notes: "", downloadURL: URL(string: "https://x/\(v).zip")!,
                      sha256: nil, sha256AssetURL: nil, sizeBytes: 1, publishedAt: nil, isPrerelease: prerelease)
    }

    func testPickUpdateStableChannel() {
        let releases = [release("1.0.0"), release("1.2.0"), release("1.3.0-rc", prerelease: true)]
        // stable → новейший НЕ-prerelease новее текущей
        XCTAssertEqual(UpdateLogic.pickUpdate(from: releases, current: "1.0.0", channel: .stable)?.version, "1.2.0")
        // нет новее → nil
        XCTAssertNil(UpdateLogic.pickUpdate(from: releases, current: "1.2.0", channel: .stable))
    }

    func testPickUpdateBetaChannel() {
        let releases = [release("1.2.0"), release("1.3.0-rc", prerelease: true)]
        // beta → включает prerelease, берёт новейший
        XCTAssertEqual(UpdateLogic.pickUpdate(from: releases, current: "1.2.0", channel: .beta)?.version, "1.3.0-rc")
    }

    func testSha256FromNotes() {
        let hash = String(repeating: "a", count: 64)
        XCTAssertEqual(UpdateLogic.sha256(fromNotes: "Release\nSHA256: \(hash)\nbye"), hash)
        XCTAssertNil(UpdateLogic.sha256(fromNotes: "no hash here"))
    }

    func testDecodeGitHubReleases() throws {
        let json = """
        [{"tag_name":"v1.5.0","body":"notes SHA256: \(String(repeating: "b", count: 64))","prerelease":false,
          "published_at":"2026-06-22T10:30:00Z",
          "assets":[{"name":"Sage-1.5.0.zip","browser_download_url":"https://x/Sage-1.5.0.zip","size":50331648},
                    {"name":"Sage-1.5.0.zip.sha256","browser_download_url":"https://x/Sage-1.5.0.zip.sha256","size":65}]}]
        """.data(using: .utf8)!
        let releases = try UpdateLogic.decodeGitHubReleases(json)
        XCTAssertEqual(releases.count, 1)
        let r = releases[0]
        XCTAssertEqual(r.version, "1.5.0")                 // снят ведущий v
        XCTAssertEqual(r.sizeBytes, 50_331_648)
        XCTAssertEqual(r.sha256, String(repeating: "b", count: 64))   // из тела
        XCTAssertNotNil(r.sha256AssetURL)
        XCTAssertFalse(r.isPrerelease)
        XCTAssertNotNil(r.publishedAt)
    }
}
