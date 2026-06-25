import CoreKit
import XCTest
@testable import AppShellFeature

@MainActor
final class AppRouterTests: XCTestCase {
    func testGoChangesView() {
        let r = AppRouter()
        r.go(.chat)
        XCTAssertEqual(r.view, .chat)
    }

    func testOpenChatSetsContextAndView() {
        let r = AppRouter()
        r.pendingChatPrompt = "stale"
        r.openChat(context: .file(name: "n", path: "/p"))
        XCTAssertEqual(r.view, .chat)
        XCTAssertEqual(r.pendingChatContext, .file(name: "n", path: "/p"))
        XCTAssertNil(r.pendingChatPrompt)
    }

    func testAskVaultSetsPromptAndBumpsNonce() {
        let r = AppRouter()
        let n0 = r.chatPromptNonce
        r.askVault(query: "find git")
        XCTAssertEqual(r.view, .chat)
        XCTAssertEqual(r.pendingChatContext, .vault)
        XCTAssertEqual(r.pendingChatPrompt, "find git")
        XCTAssertEqual(r.chatPromptNonce, n0 + 1)
    }

    func testOpenSettings() {
        let r = AppRouter()
        r.openSettings(tab: .general)
        XCTAssertEqual(r.view, .settings)
        XCTAssertEqual(r.settingsTab, .general)
    }

    func testToggleSidebar() {
        let r = AppRouter()
        let initial = r.sidebarOpen
        r.toggleSidebar()
        XCTAssertEqual(r.sidebarOpen, !initial)
    }

    func testInvokeInlineAINonce() {
        let r = AppRouter()
        let n0 = r.inlineAINonce
        r.invokeInlineAI()
        XCTAssertEqual(r.inlineAINonce, n0 + 1)
    }
}
