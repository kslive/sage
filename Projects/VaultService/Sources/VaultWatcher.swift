import CoreServices
import Foundation

/// Живое наблюдение за деревом хранилища через FSEvents: внешние изменения (Finder, git, синки)
/// сразу триггерят перестроение дерева — не только при реактивации окна.
/// Игнорирует события собственного процесса (свои сохранения мы и так перезагружаем явно).
@MainActor
public final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private var handler: (() -> Void)?

    public init() {}

    /// Начать наблюдение за `root` (рекурсивно). `onChange` вызывается на главном потоке, с дебаунсом ~0.5с.
    public func start(root: URL, onChange: @escaping () -> Void) {
        stop()
        handler = onChange
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.handler?() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        handler = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
