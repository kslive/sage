import Foundation
import XCTest
@testable import CoreKit

/// SecretStore — device-bound шифрованные файлы вместо кейчейна (нет диалогов после обновлений).
/// Тесты используют уникальные account-имена и чистят за собой (реальная папка Secrets).
final class SecretStoreTests: XCTestCase {
    private var account = ""

    override func setUp() {
        super.setUp()
        account = "test.secret.\(UUID().uuidString)"
    }

    override func tearDown() {
        SecretStore.delete(account: account)
        UserDefaults.standard.removeObject(forKey: "sage.secret.deleted.\(account)")
        super.tearDown()
    }

    func testRoundTrip() {
        SecretStore.set("sk-очень-секретно", account: account)
        XCTAssertEqual(SecretStore.get(account: account), "sk-очень-секретно")
        SecretStore.set("obnovlённый", account: account)
        XCTAssertEqual(SecretStore.get(account: account), "obnovlённый")
    }

    func testNilOrEmptySetDeletes() {
        SecretStore.set("value", account: account)
        SecretStore.set(nil, account: account)
        XCTAssertNil(SecretStore.get(account: account))
        SecretStore.set("value", account: account)
        SecretStore.set("", account: account)
        XCTAssertNil(SecretStore.get(account: account))
    }

    func testDeleteRemoves() {
        SecretStore.set("value", account: account)
        SecretStore.delete(account: account)
        XCTAssertNil(SecretStore.get(account: account))
    }

    /// Per-vault account содержит «/» — файл обязан лечь внутрь Secrets (percent-encoding), не в подпапки.
    func testSlashInAccountIsSafe() {
        let slashy = "test.secret.\(UUID().uuidString):/Users/me/Vault"
        defer {
            SecretStore.delete(account: slashy)
            UserDefaults.standard.removeObject(forKey: "sage.secret.deleted.\(slashy)")
        }
        SecretStore.set("token", account: slashy)
        XCTAssertEqual(SecretStore.get(account: slashy), "token")
    }

    func testGitTokenAccountPerVault() {
        XCTAssertNotEqual(SecretStore.gitTokenAccount(for: "/a"), SecretStore.gitTokenAccount(for: "/b"))
        XCTAssertNotEqual(SecretStore.gitTokenAccount(for: "/a"), SecretStore.gitTokenAccount)
    }
}

/// Декодеры DeepSeek-ответов (без сети).
final class DeepSeekClientTests: XCTestCase {
    func testDecodeModels() throws {
        let json = #"{"object":"list","data":[{"id":"deepseek-chat","object":"model"},{"id":"deepseek-reasoner","object":"model"}]}"#
        XCTAssertEqual(try DeepSeekClient.decodeModels(Data(json.utf8)), ["deepseek-chat", "deepseek-reasoner"])
    }

    func testDecodeChat() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"  Привет!  "}}]}"#
        XCTAssertEqual(try DeepSeekClient.decodeChat(Data(json.utf8)), "Привет!")
    }

    func testDecodeChatEmptyThrows() {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#
        XCTAssertThrowsError(try DeepSeekClient.decodeChat(Data(json.utf8)))
        XCTAssertThrowsError(try DeepSeekClient.decodeChat(Data(#"{"choices":[]}"#.utf8)))
    }
}
