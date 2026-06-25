import CoreKit
import XCTest
@testable import AppShellFeature

@MainActor
final class SidebarTaskStatusTests: XCTestCase {
    private func file(_ p: String) -> FileNode {
        FileNode(name: (p as NSString).lastPathComponent, url: URL(fileURLWithPath: p), isDirectory: false, depth: 1)
    }
    private func dir(_ p: String) -> FileNode {
        FileNode(name: (p as NSString).lastPathComponent, url: URL(fileURLWithPath: p), isDirectory: true, depth: 1)
    }

    func testNoTaskNoPhase() {
        XCTAssertNil(nodeAIPhase(file("/v/a.md"), AITaskRegistry()))
        XCTAssertNil(nodeAIPhase(dir("/v/F"), AITaskRegistry()))
    }

    func testFileInlineRunning() {
        let r = AITaskRegistry()
        r.started(.inline(path: "/v/a.md"), label: "a", route: .openInline(path: "/v/a.md"))
        XCTAssertEqual(nodeAIPhase(file("/v/a.md"), r), .running)
    }

    func testFileChatReadyUnread() {
        let r = AITaskRegistry()
        let key = AITaskKey.chat(.file(name: "a", path: "/v/a.md"))
        r.started(key, label: "a", route: .openChat(.file(name: "a", path: "/v/a.md")))
        r.finished(key)
        XCTAssertEqual(nodeAIPhase(file("/v/a.md"), r), .readyUnread)
    }

    func testFolderChatRunning() {
        let r = AITaskRegistry()
        let key = AITaskKey.chat(.folder(name: "F", fileCount: 0, path: "/v/F"))
        r.started(key, label: "F", route: .openChat(.folder(name: "F", fileCount: 0, path: "/v/F")))
        XCTAssertEqual(nodeAIPhase(dir("/v/F"), r), .running)
        // файл не должен подхватывать статус папки и наоборот
        XCTAssertNil(nodeAIPhase(file("/v/F"), r))
    }

    func testRunningBeatsReadyUnread() {
        let r = AITaskRegistry()
        r.started(.inline(path: "/v/a.md"), label: "a", route: .openInline(path: "/v/a.md"))   // running
        let chat = AITaskKey.chat(.file(name: "a", path: "/v/a.md"))
        r.started(chat, label: "a", route: .openChat(.file(name: "a", path: "/v/a.md")))
        r.finished(chat)                                                                         // readyUnread
        XCTAssertEqual(nodeAIPhase(file("/v/a.md"), r), .running)
    }

    /// Свойство, на котором держится фикс «✦ инлайна гаснет при возврате в редактор» (RootView
    /// onChange(router.view → .editor) → markRead(.inline)): markRead гасит readyUnread, но НЕ трогает running.
    func testMarkReadInlineClearsReadyUnreadButNotRunning() {
        let r = AITaskRegistry()
        let key = AITaskKey.inline(path: "/v/a.md")
        // running → markRead — no-op (спиннер генерации не гасим)
        r.started(key, label: "a", route: .openInline(path: "/v/a.md"))
        r.markRead(key)
        XCTAssertEqual(nodeAIPhase(file("/v/a.md"), r), .running)
        // finished → readyUnread (✦) → markRead гасит
        r.finished(key)
        XCTAssertEqual(nodeAIPhase(file("/v/a.md"), r), .readyUnread)
        r.markRead(key)
        XCTAssertNil(nodeAIPhase(file("/v/a.md"), r), "возврат в редактор должен погасить ✦ инлайна")
    }
}
