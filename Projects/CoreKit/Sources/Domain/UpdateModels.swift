import Foundation

/// Доступный релиз приложения (распарсенный из GitHub Releases).
public struct UpdateRelease: Sendable, Equatable {
    public let version: String
    public let notes: String
    public let downloadURL: URL
    public let sha256: String?
    public let sha256AssetURL: URL?
    public let sizeBytes: Int64
    public let publishedAt: Date?
    public let isPrerelease: Bool

    public init(version: String, notes: String, downloadURL: URL, sha256: String?,
                sha256AssetURL: URL?, sizeBytes: Int64, publishedAt: Date?, isPrerelease: Bool) {
        self.version = version
        self.notes = notes
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.sha256AssetURL = sha256AssetURL
        self.sizeBytes = sizeBytes
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
    }
}

/// Прогресс скачивания обновления.
public struct UpdateProgress: Sendable, Equatable {
    public let received: Int64
    public let total: Int64
    public init(received: Int64, total: Int64) { self.received = received; self.total = total }
    public var fraction: Double { total > 0 ? min(1, max(0, Double(received) / Double(total))) : 0 }
}

/// Фаза апдейтера для UI вкладки «Обновления» (макет Section 8).
public enum UpdaterPhase: Sendable, Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(UpdateRelease)
    case downloading(Double)
    case readyToInstall(UpdateRelease)
    case installing
    case failed(String)
}

/// Канал обновлений: стабильный или бета (включает prerelease).
public enum UpdateChannel: String, Sendable, CaseIterable { case stable, beta }

/// Чистая логика апдейтера (сравнение версий, выбор релиза, парс SHA) — тестируется без сети.
public enum UpdateLogic {
    /// Числовое сравнение semver «1.5.0»/«v1.5»/«1.5.0-beta.1». Возвращает -1/0/1.
    /// Пререлизный суффикс (после `-`) игнорируется при сравнении ядра версии.
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        func core(_ s: String) -> [Int] {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            let noV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
            let base = noV.split(separator: "-", maxSplits: 1).first.map(String.init) ?? noV
            return base.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let x = core(a), y = core(b)
        for i in 0 ..< max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    /// `candidate` строго новее `current`?
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compareVersions(candidate, current) > 0
    }

    /// Выбрать новейший подходящий по каналу релиз, который НОВЕЕ текущей версии (иначе nil).
    /// stable → только не-prerelease; beta → любой (включая prerelease).
    public static func pickUpdate(from releases: [UpdateRelease], current: String,
                                  channel: UpdateChannel) -> UpdateRelease? {
        releases
            .filter { channel == .beta || !$0.isPrerelease }
            .filter { isNewer($0.version, than: current) }
            .max { compareVersions($0.version, $1.version) < 0 }
    }

    /// Достать SHA-256 (64 hex) из текста release notes (строка `SHA256: <hash>` или просто хэш).
    public static func sha256(fromNotes notes: String) -> String? {
        guard let range = notes.range(of: "[a-fA-F0-9]{64}", options: .regularExpression) else { return nil }
        return notes[range].lowercased()
    }

    /// Декод JSON-ответа GitHub `/releases` → массив `UpdateRelease` (берём zip-ассет + sidecar `.sha256`).
    public static func decodeGitHubReleases(_ data: Data) throws -> [UpdateRelease] {
        let raw = try JSONDecoder().decode([GHRelease].self, from: data)
        let iso = ISO8601DateFormatter()
        return raw.compactMap { r in
            guard let zip = r.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
                  let url = URL(string: zip.browser_download_url) else { return nil }
            let shaAsset = r.assets.first { $0.name.lowercased().hasSuffix(".sha256") }
            let version = (r.tag_name.hasPrefix("v") || r.tag_name.hasPrefix("V"))
                ? String(r.tag_name.dropFirst()) : r.tag_name
            return UpdateRelease(
                version: version,
                notes: r.body ?? "",
                downloadURL: url,
                sha256: sha256(fromNotes: r.body ?? ""),
                sha256AssetURL: shaAsset.flatMap { URL(string: $0.browser_download_url) },
                sizeBytes: zip.size,
                publishedAt: r.published_at.flatMap { iso.date(from: $0) },
                isPrerelease: r.prerelease
            )
        }
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let body: String?
        let prerelease: Bool
        let published_at: String?
        let assets: [GHAsset]
    }
    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
    }
}
