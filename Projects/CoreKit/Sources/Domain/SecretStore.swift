import CryptoKit
import Foundation
import IOKit
import Security

/// Секреты приложения (git-токен, API-ключи) — device-bound шифрованные ФАЙЛЫ вместо
/// login-кейчейна.
///
/// ПОЧЕМУ НЕ KEYCHAIN: приложение подписано ad-hoc/self-signed, а кейчейн охраняет каждый
/// итем ДВУМЯ независимыми проверками. ACL на чтение можно сделать разрешительным, но
/// PARTITION LIST — нельзя: securityd штампует его cdhash'ем создавшего бинаря, публичного
/// API у него нет, а правка требует пароль связки ключей. Каждое обновление ad-hoc-приложения —
/// новый cdhash, поэтому macOS требовала пароль кейчейна ПОСЛЕ КАЖДОГО обновления, всегда.
/// Не «чинить» это обратно на SecItem-хранение.
///
/// Схема: AES-GCM с ключом из IOPlatformUUID мака, файл 0600 в Application Support/Sage/Secrets.
/// Честно о модели угроз: любой процесс под пользователем может повторить деривацию — та же
/// планка, что был бы у кейчейн-итема без промпта. Шифртекст всё же побеждает сканеры секретов
/// и попадание в бэкапы открытым текстом; ключ не покидает машину (копия на другом маке не
/// расшифруется → пользователь просто вводит секрет заново).
public enum SecretStore {
    /// Общий git-токен (legacy, один на приложение) — фолбэк для хранилищ, подключённых
    /// до per-vault ключей.
    public static let gitTokenAccount = "sage.git.token"
    /// DeepSeek API-ключ (облачный путь ИИ; nil = выключен).
    public static let deepseekKeyAccount = "sage.deepseek.key"

    private static let keychainService = "com.sage.app"
    private static let salt = "com.sage.app.secret-store.v1"
    private static let migrationLock = NSLock()
    private nonisolated(unsafe) static var migrationAttempted = Set<String>()

    /// Аккаунт git-токена КОНКРЕТНОГО хранилища (per-vault) — репозитории не делят токен.
    public static func gitTokenAccount(for vaultPath: String) -> String {
        "sage.git.token:" + vaultPath
    }

    public static func get(account: String) -> String? {
        if let data = try? Data(contentsOf: fileURL(account)),
           let box = try? AES.GCM.SealedBox(combined: data),
           let plain = try? AES.GCM.open(box, using: deviceKey()) {
            return String(data: plain, encoding: .utf8)
        }
        return migrateFromKeychain(account)
    }

    /// nil/пустая строка = удалить секрет.
    public static func set(_ value: String?, account: String) {
        guard let value, !value.isEmpty else { delete(account: account); return }
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: deviceKey()),
              let combined = sealed.combined else { return }
        let url = fileURL(account)
        do {
            try combined.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { return }
        UserDefaults.standard.removeObject(forKey: tombstoneKey(account))
        keychainDelete(account)
    }

    public static func delete(account: String) {
        UserDefaults.standard.set(true, forKey: tombstoneKey(account))
        keychainDelete(account)
        try? FileManager.default.removeItem(at: fileURL(account))
    }

    /// Постоянный надгробный камень: после ЯВНОГО удаления миграция из кейчейна не должна
    /// воскресить значение на следующем запуске. Снимается следующим `set`.
    private static func tombstoneKey(_ account: String) -> String {
        "sage.secret.deleted.\(account)"
    }

    /// Имя файла: percent-encode, т.к. per-vault account содержит «/» из пути хранилища.
    private static func fileURL(_ account: String) -> URL {
        let dir = secretsDirectory()
        let safe = account.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? account
        return dir.appendingPathComponent(safe)
    }

    private static func secretsDirectory() -> URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("Sage/Secrets", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        return dir
    }

    /// SHA-256(IOPlatformUUID + salt) → AES-ключ. Аппаратный UUID стабилен между обновлениями
    /// приложения и переустановками ОС, но уникален для машины.
    private static func deviceKey() -> SymmetricKey {
        SymmetricKey(data: Data(SHA256.hash(data: Data((deviceUUID() + salt).utf8))))
    }

    private static func deviceUUID() -> String {
        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        guard entry != 0 else { return "sage-no-ioreg" }
        defer { IOObjectRelease(entry) }
        let prop = IORegistryEntryCreateCFProperty(
            entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0
        )
        return prop?.takeRetainedValue() as? String ?? "sage-no-ioreg"
    }

    /// Секреты старых сборок живут в login-кейчейне. Чтение из нового бинаря может показать
    /// ОДИН последний диалог подтверждения — после успешного чтения значение переезжает в
    /// шифрованный файл, кейчейн-итем удаляется, и диалог не возвращается. Одна попытка на
    /// запуск: отклонённый диалог не должен долбить на каждый sync.
    private static func migrateFromKeychain(_ account: String) -> String? {
        guard !UserDefaults.standard.bool(forKey: tombstoneKey(account)) else { return nil }
        migrationLock.lock()
        let seen = migrationAttempted.contains(account)
        if !seen { migrationAttempted.insert(account) }
        migrationLock.unlock()
        guard !seen else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        set(value, account: account)
        return value
    }

    private static func keychainDelete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
