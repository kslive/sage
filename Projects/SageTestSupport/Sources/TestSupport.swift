import CoreKit
import Foundation
import Localization
import SettingsStore

/// Изолированный SettingsStore на собственном suite — тесты не трогают реальные настройки.
@MainActor
public func makeSettings() -> SettingsStore {
    let suite = UserDefaults(suiteName: "test." + UUID().uuidString)!
    return SettingsStore(defaults: suite)
}

/// Изолированный LocaleManager (свой suite, заданный язык).
@MainActor
public func makeLocale(_ language: AppLanguage = .ru) -> LocaleManager {
    let suite = UserDefaults(suiteName: "test.locale." + UUID().uuidString)!
    return LocaleManager(language: language, defaults: suite)
}

/// Счётчик вызовов замыкания (reference type — чтобы замыкание писало в него).
public final class FinishSpy: @unchecked Sendable {
    public private(set) var count = 0
    public init() {}
    public func fire() { count += 1 }
}

/// Временный каталог-хранилище для тестов файловых сервисов (автоудаление).
public final class TempVault {
    public let root: URL
    private let fm = FileManager.default

    public init() {
        root = fm.temporaryDirectory.appendingPathComponent("sage-test-" + UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Записать заметку по относительному пути, создав промежуточные папки. Возвращает URL.
    @discardableResult
    public func write(_ relativePath: String, _ text: String = "# note\n") -> URL {
        let url = root.appendingPathComponent(relativePath)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Создать вложенную папку, вернуть URL.
    @discardableResult
    public func folder(_ relativePath: String) -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func cleanup() { try? fm.removeItem(at: root) }
    deinit { try? fm.removeItem(at: root) }
}

/// Собрать все элементы асинхронного потока в массив (для проверок в тестах).
public func collect<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var out: [T] = []
    for try await item in stream { out.append(item) }
    return out
}

public func collect<T>(_ stream: AsyncStream<T>) async -> [T] {
    var out: [T] = []
    for await item in stream { out.append(item) }
    return out
}
