import CoreKit
import Foundation

/// Хранилище истории чатов (JSON в Application Support).
public actor ChatStore: ChatStoring {
    private let url: URL
    private var cache: [ChatSession] = []
    private var loaded = false

    public init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("Sage", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("chats.json")
    }

    /// Инициализатор с явным каталогом — для изоляции в тестах (temp-директория).
    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("chats.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url) else { return }
        cache = (try? JSONDecoder().decode([ChatSession].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func sessions() async -> [ChatSession] {
        loadIfNeeded()
        return cache.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ session: ChatSession) async {
        loadIfNeeded()
        if let index = cache.firstIndex(where: { $0.id == session.id }) {
            cache[index] = session
        } else {
            cache.append(session)
        }
        persist()
    }

    public func delete(id: UUID) async {
        loadIfNeeded()
        cache.removeAll { $0.id == id }
        persist()
    }
}
