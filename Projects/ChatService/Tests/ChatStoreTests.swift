import CoreKit
import Foundation
import XCTest
@testable import ChatService

final class ChatStoreTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        dir = fm.temporaryDirectory.appendingPathComponent("cs-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: dir)
        super.tearDown()
    }

    private func session(_ title: String, updated: TimeInterval) -> ChatSession {
        ChatSession(
            id: UUID(), title: title, context: .vault,
            messages: [ChatMessage(id: UUID(), role: .user, text: "hi", createdAt: Date())],
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    func testSaveThenSessions() async {
        let store = ChatStore(directory: dir)
        let s = session("A", updated: 100)
        await store.save(s)
        let all = await store.sessions()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "A")
    }

    func testSessionsSortedByUpdatedDesc() async {
        let store = ChatStore(directory: dir)
        await store.save(session("old", updated: 100))
        await store.save(session("new", updated: 200))
        let all = await store.sessions()
        XCTAssertEqual(all.map(\.title), ["new", "old"])
    }

    func testUpsertSameID() async {
        let store = ChatStore(directory: dir)
        var s = session("A", updated: 100)
        await store.save(s)
        s.title = "A-updated"
        await store.save(s)
        let all = await store.sessions()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "A-updated")
    }

    func testDelete() async {
        let store = ChatStore(directory: dir)
        let s = session("A", updated: 100)
        await store.save(s)
        await store.delete(id: s.id)
        let all = await store.sessions()
        XCTAssertTrue(all.isEmpty)
    }

    func testPersistAcrossInstances() async {
        let s = session("Persisted", updated: 100)
        let store1 = ChatStore(directory: dir)
        await store1.save(s)
        let store2 = ChatStore(directory: dir)
        let all = await store2.sessions()
        XCTAssertEqual(all.first?.title, "Persisted")
    }

    func testEmptyStore() async {
        let store = ChatStore(directory: dir)
        let all = await store.sessions()
        XCTAssertTrue(all.isEmpty)
    }
}
