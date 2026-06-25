import CoreKit
import Foundation
import Observation

/// Центр всплывающих уведомлений (тостов) с авто-скрытием.
@MainActor
@Observable
public final class ToastCenter {
    public private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ toast: Toast) {
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    public func success(_ icon: String, _ text: String) { show(Toast(icon: icon, text: text, kind: .success)) }
    public func error(_ icon: String, _ text: String) { show(Toast(icon: icon, text: text, kind: .error)) }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
