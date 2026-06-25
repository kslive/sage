import Foundation

/// Прогресс загрузки файла модели.
public struct DownloadProgress: Sendable, Equatable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64
    public let speedBytesPerSec: Double

    public init(downloadedBytes: Int64, totalBytes: Int64, speedBytesPerSec: Double) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSec = speedBytesPerSec
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    public var percent: Int { Int((fraction * 100).rounded()) }
}

/// Состояние модели на диске / процесс её загрузки.
public enum DownloadState: Sendable, Equatable {
    case notInstalled
    case downloading(DownloadProgress)
    case verifying
    case installed
    case failed(message: String)

    public var isInstalled: Bool { if case .installed = self { true } else { false } }
    public var isActive: Bool {
        switch self {
        case .downloading, .verifying: true
        default: false
        }
    }
    public var isFailed: Bool { if case .failed = self { true } else { false } }
}

/// Ошибки загрузчика моделей.
public enum DownloadError: LocalizedError, Sendable {
    case network
    case cancelled
    case invalidFile
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .network: "Нет соединения"
        case .cancelled: "Загрузка отменена"
        case .invalidFile: "Файл повреждён"
        case let .server(code): "Ошибка сервера (\(code))"
        }
    }
}
