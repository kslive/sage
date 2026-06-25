import Foundation

/// Пути хранения локальных моделей.
public enum ModelStorage {
    public static func baseDirectory() -> URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("Sage/models", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func llmDirectory() -> URL {
        let dir = baseDirectory().appendingPathComponent("llm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func whisperDirectory() -> URL {
        let dir = baseDirectory().appendingPathComponent("whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// База для HubApi-загрузки MLX-моделей (репозитории качаются в `<llm>/models/<repoId>`).
    public static func llmHubBase() -> URL { llmDirectory() }

    /// Локальная папка скачанной MLX-модели по её HF-repoId.
    public static func llmModelDirectory(repoId: String) -> URL {
        llmDirectory().appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(repoId, isDirectory: true)
    }

    /// Валидна ли скачанная MLX-модель: есть config.json и хотя бы один файл весов.
    public static func isValidModelDir(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent("config.json").path) else { return false }
        let files = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        return files.contains { $0.hasSuffix(".safetensors") }
    }

    public static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil ?? 0
    }

    /// Суммарный размер всех файлов в папке (рекурсивно) — реальный объём скачанного на диске.
    /// Учитывает и временные `.incomplete`-файлы (растут по мере загрузки); несуществующая папка → 0.
    public static func directoryByteSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                     options: [], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in en {
            let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if vals?.isRegularFile == true { total += Int64(vals?.fileSize ?? 0) }
        }
        return total
    }

    /// Валиден ли скачанный файл (размер в пределах 80–110 % ожидаемого).
    public static func isValid(url: URL, expected: Int64) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = fileSize(at: url)
        guard size > 0 else { return false }
        let min = Int64(Double(expected) * 0.8)
        let max = Int64(Double(expected) * 1.15)
        return size >= min && size <= max
    }

    /// Проверка GGUF-сигнатуры (первые 4 байта).
    public static func hasGGUFMagic(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magics: [[UInt8]] = [
            Array("GGUF".utf8), Array("ggml".utf8), Array("ggjt".utf8), Array("ggla".utf8),
        ]
        return magics.contains(Array(data))
    }
}
