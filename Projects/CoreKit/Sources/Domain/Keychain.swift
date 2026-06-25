import Foundation
import Security

/// Тонкая обёртка над Keychain для секретов (например, Git HTTPS-токен).
public enum Keychain {
    /// Legacy-общий аккаунт токена (один на приложение). Используется как ФОЛБЭК для уже подключённых
    /// хранилищ, пока их не переподключат под per-vault ключ.
    public static let gitTokenAccount = "sage.git.token"
    private static let service = "com.sage.app"

    /// Аккаунт git-токена для КОНКРЕТНОГО хранилища (per-vault) — чтобы разные репозитории не делили токен.
    public static func gitTokenAccount(for vaultPath: String) -> String {
        "sage.git.token:" + vaultPath
    }

    public static func set(_ value: String?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8), !data.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}
