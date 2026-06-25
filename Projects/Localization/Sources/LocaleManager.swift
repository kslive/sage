import CoreKit
import Foundation
import Observation

/// Источник истины для языка интерфейса. Меняется в рантайме —
/// весь UI, подписанный через `@Environment(LocaleManager.self)`, перерисовывается.
@Observable
public final class LocaleManager {
    public private(set) var language: AppLanguage
    private let defaultsKey = "sage.language"
    private let defaults: UserDefaults

    public init(language: AppLanguage? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let language {
            self.language = language
        } else {
            let saved = defaults.string(forKey: defaultsKey)
            self.language = saved.flatMap(AppLanguage.init(rawValue:))
                ?? AppLanguage.fromSystem(Locale.preferredLanguages)
        }
    }

    /// Текущий набор строк.
    public var strings: Strings {
        switch language {
        case .ru: .ru
        case .en: .en
        case .zh: .zh
        }
    }

    public func setLanguage(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: defaultsKey)
    }
}
