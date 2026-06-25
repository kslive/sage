import ProjectDescription

/// Общие настройки и фабрики таргетов для проекта Sage.
public enum Sage {
    public static let orgPrefix = "com.sage"
    public static let deployment: DeploymentTargets = .macOS("15.0")
    public static let destinations: Destinations = [.mac]
    public static let swiftVersion = "5.0"

    /// Базовые build-настройки для всех таргетов: неподписанная (ad-hoc) сборка.
    public static var baseSettings: SettingsDictionary {
        [
            "SWIFT_VERSION": .string(swiftVersion),
            "CODE_SIGN_IDENTITY": "-",
            "CODE_SIGN_STYLE": "Manual",
            "DEVELOPMENT_TEAM": "",
            "PROVISIONING_PROFILE_SPECIFIER": "",
            "CODE_SIGNING_REQUIRED": "NO",
            "ENABLE_HARDENED_RUNTIME": "NO",
            "MARKETING_VERSION": "1.0.0",
            "CURRENT_PROJECT_VERSION": "1",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            "DEAD_CODE_STRIPPING": "YES",
        ]
    }

    /// Фреймворк-модуль. Исходники: `Projects/<name>/Sources/**`.
    public static func framework(
        _ name: String,
        dependencies: [TargetDependency] = [],
        hasResources: Bool = false
    ) -> Target {
        .target(
            name: name,
            destinations: destinations,
            product: .framework,
            bundleId: "\(orgPrefix).\(name)",
            deploymentTargets: deployment,
            infoPlist: .default,
            sources: ["Projects/\(name)/Sources/**"],
            resources: hasResources ? ["Projects/\(name)/Resources/**"] : nil,
            dependencies: dependencies,
            settings: .settings(base: baseSettings)
        )
    }

    /// Юнит-тест-таргет для модуля. Исходники: `Projects/<name>/Tests/**`.
    public static func unitTests(
        for name: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: "\(name)Tests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "\(orgPrefix).\(name)Tests",
            deploymentTargets: deployment,
            infoPlist: .default,
            sources: ["Projects/\(name)/Tests/**"],
            dependencies: dependencies + [.target(name: name)],
            settings: .settings(base: baseSettings)
        )
    }
}

public extension TargetDependency {
    /// Краткая запись зависимости на локальный модуль.
    static func module(_ name: String) -> TargetDependency { .target(name: name) }
}
