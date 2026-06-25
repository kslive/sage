import Foundation
import XCTest
@testable import CoreKit

@MainActor
final class AITaskRegistryTests: XCTestCase {
    private let fileKey = AITaskKey.inline(path: "/v/a.md")
    private let chatKey = AITaskKey.chat(.vault)

    func testKeyRawMatchesChatKeyScheme() {
        XCTAssertEqual(AITaskKey.chat(.vault).raw, "vault")
        XCTAssertEqual(AITaskKey.chat(.file(name: "a", path: "/v/a.md")).raw, "file:/v/a.md")
        XCTAssertEqual(AITaskKey.chat(.folder(name: "F", fileCount: 3, path: "/v/F")).raw, "folder:/v/F")
        XCTAssertEqual(AITaskKey.chat(.selection(fileName: "n.md")).raw, "selection:n.md")
        XCTAssertEqual(AITaskKey.inline(path: "/v/a.md").raw, "inline:/v/a.md")
    }

    func testTransitions() {
        let r = AITaskRegistry()
        r.started(fileKey, label: "a.md", route: .openInline(path: "/v/a.md"))
        XCTAssertTrue(r.isRunning(fileKey))
        r.finished(fileKey)
        XCTAssertTrue(r.isReadyUnread(fileKey))
        XCTAssertFalse(r.isRunning(fileKey))
        r.markRead(fileKey)
        XCTAssertNil(r.phase(fileKey))
    }

    func testFailedSetsError() {
        let r = AITaskRegistry()
        r.started(chatKey, label: "vault", route: .openChat(.vault))
        r.failed(chatKey)
        XCTAssertEqual(r.phase(chatKey), .error)
    }

    func testStartedOverwritesBackToRunning() {
        let r = AITaskRegistry()
        r.started(fileKey, label: "a.md", route: .openInline(path: "/v/a.md"))
        r.finished(fileKey)
        XCTAssertTrue(r.isReadyUnread(fileKey))
        r.started(fileKey, label: "a.md", route: .openInline(path: "/v/a.md"))   // повторный запуск
        XCTAssertTrue(r.isRunning(fileKey))
    }

    func testFinishFailMarkReadOnMissingAreNoOps() {
        let r = AITaskRegistry()
        r.finished(fileKey)            // нет записи
        r.failed(fileKey)
        r.markRead(fileKey)
        XCTAssertTrue(r.entries.isEmpty)
        XCTAssertNil(r.phase(fileKey))
    }

    func testMarkReadKeepsRunningButCancelClears() {
        let r = AITaskRegistry()
        r.started(fileKey, label: "f", route: .openInline(path: "/v/a.md"))
        r.markRead(fileKey)                       // running — markRead НЕ снимает (клик/навигация не гасят спиннер)
        XCTAssertEqual(r.phase(fileKey), .running)
        r.cancel(fileKey)                         // отмена — снимает даже running
        XCTAssertNil(r.phase(fileKey))
        // readyUnread markRead снимает как обычно
        r.started(fileKey, label: "f", route: .openInline(path: "/v/a.md"))
        r.finished(fileKey)
        r.markRead(fileKey)
        XCTAssertNil(r.phase(fileKey))
    }

    func testFolderHasUnread() {
        let r = AITaskRegistry()
        let folder = AITaskKey.chat(.folder(name: "F", fileCount: 2, path: "/v/F"))
        r.started(folder, label: "F/", route: .openChat(.folder(name: "F", fileCount: 2, path: "/v/F")))
        XCTAssertFalse(r.folderHasUnread(path: "/v/F"))   // ещё running
        r.finished(folder)
        XCTAssertTrue(r.folderHasUnread(path: "/v/F"))
        XCTAssertFalse(r.folderHasUnread(path: "/v/Other"))
    }

    func testPruneRemovesUnkept() {
        let r = AITaskRegistry()
        r.started(.inline(path: "/v/a.md"), label: "a", route: .openInline(path: "/v/a.md"))
        r.started(.inline(path: "/v/gone.md"), label: "g", route: .openInline(path: "/v/gone.md"))
        r.prune { $0 == "inline:/v/a.md" }
        XCTAssertNotNil(r.phase(.inline(path: "/v/a.md")))
        XCTAssertNil(r.phase(.inline(path: "/v/gone.md")))
    }
}
