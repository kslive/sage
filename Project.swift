import ProjectDescription
import ProjectDescriptionHelpers

// MARK: - Core

let coreKit = Sage.framework("CoreKit")

let localization = Sage.framework(
    "Localization",
    dependencies: [.module("CoreKit")]
)

let designSystem = Sage.framework(
    "DesignSystem",
    dependencies: [.module("CoreKit")],
    hasResources: true // бандлим Resources/Fonts (Cabinet Grotesk / General Sans)
)

// MARK: - Services

let settingsStore = Sage.framework("SettingsStore", dependencies: [.module("CoreKit")])
let vaultService = Sage.framework("VaultService", dependencies: [.module("CoreKit")])
let markdownService = Sage.framework("MarkdownService", dependencies: [.module("CoreKit")])
let gitService = Sage.framework("GitService", dependencies: [.module("CoreKit")])
let updateService = Sage.framework("UpdateService", dependencies: [.module("CoreKit")])
let modelService = Sage.framework("ModelService", dependencies: [.module("CoreKit"), .external(name: "Transformers")])
let inferenceService = Sage.framework("InferenceService", dependencies: [.module("CoreKit"), .module("ModelService"), .external(name: "MLXLLM"), .external(name: "MLXLMCommon")])
let speechService = Sage.framework("SpeechService", dependencies: [.module("CoreKit"), .module("ModelService"), .external(name: "SwiftWhisper")])
let chatService = Sage.framework("ChatService", dependencies: [.module("CoreKit")])

// MARK: - Features

let uiDeps: [TargetDependency] = [.module("CoreKit"), .module("DesignSystem"), .module("Localization")]

let appShellFeature = Sage.framework(
    "AppShellFeature",
    dependencies: uiDeps + [.module("SettingsStore")]
)
let onboardingFeature = Sage.framework(
    "OnboardingFeature",
    dependencies: uiDeps + [.module("ModelService"), .module("VaultService"), .module("SettingsStore")]
)
let onboardingFeatureTests = Sage.unitTests(
    for: "OnboardingFeature",
    dependencies: [.module("CoreKit"), .module("Localization"), .module("SettingsStore"), .module("ModelService"), .module("SageTestSupport")]
)
let editorFeature = Sage.framework(
    "EditorFeature",
    dependencies: uiDeps + [.module("VaultService"), .module("MarkdownService"), .module("InferenceService")],
    hasResources: true // editor/ (CodeMirror 6 bundle + index.html)
)
let chatFeature = Sage.framework(
    "ChatFeature",
    dependencies: uiDeps + [.module("ChatService"), .module("InferenceService"), .module("SpeechService"), .module("VaultService")]
)
let searchFeature = Sage.framework(
    "SearchFeature",
    dependencies: uiDeps + [.module("VaultService"), .module("MarkdownService"), .module("InferenceService")]
)
let settingsFeature = Sage.framework(
    "SettingsFeature",
    dependencies: uiDeps + [.module("SettingsStore"), .module("ModelService"), .module("GitService"), .module("UpdateService"), .module("InferenceService"), .module("SpeechService")]
)

// MARK: - Test support + test targets

let sageTestSupport = Sage.framework(
    "SageTestSupport",
    dependencies: [.module("CoreKit"), .module("SettingsStore"), .module("Localization"), .module("VaultService"), .module("MarkdownService")]
)
let coreKitTests = Sage.unitTests(for: "CoreKit")
let designSystemTests = Sage.unitTests(for: "DesignSystem", dependencies: [.module("CoreKit")])
let localizationTests = Sage.unitTests(for: "Localization", dependencies: [.module("CoreKit")])
let vaultServiceTests = Sage.unitTests(for: "VaultService", dependencies: [.module("CoreKit"), .module("SageTestSupport")])
let markdownServiceTests = Sage.unitTests(for: "MarkdownService", dependencies: [.module("CoreKit")])
let modelServiceTests = Sage.unitTests(for: "ModelService", dependencies: [.module("CoreKit"), .module("SageTestSupport")])
let settingsStoreTests = Sage.unitTests(for: "SettingsStore", dependencies: [.module("CoreKit"), .module("SageTestSupport")])
let chatServiceTests = Sage.unitTests(for: "ChatService", dependencies: [.module("CoreKit")])
let appShellFeatureTests = Sage.unitTests(for: "AppShellFeature", dependencies: uiDeps + [.module("SettingsStore"), .module("SageTestSupport")])
let chatFeatureTests = Sage.unitTests(for: "ChatFeature", dependencies: [.module("CoreKit"), .module("SageTestSupport")])
let editorFeatureTests = Sage.unitTests(for: "EditorFeature", dependencies: [.module("CoreKit"), .module("SageTestSupport"), .module("VaultService"), .module("MarkdownService")])
let searchFeatureTests = Sage.unitTests(for: "SearchFeature", dependencies: [.module("CoreKit"), .module("SageTestSupport"), .module("MarkdownService")])
let gitServiceTests = Sage.unitTests(for: "GitService", dependencies: [.module("CoreKit")])
let updateServiceTests = Sage.unitTests(for: "UpdateService", dependencies: [.module("CoreKit")])
let settingsFeatureTests = Sage.unitTests(
    for: "SettingsFeature",
    dependencies: [.module("CoreKit"), .module("Localization"), .module("SettingsStore"), .module("UpdateService"), .module("SageTestSupport")]
)
// App-таргет называется "Sage" (не "App") — тест-таргет объявляем вручную, цель `.target("Sage")`.
let appTests = Target.target(
    name: "AppTests",
    destinations: Sage.destinations,
    product: .unitTests,
    bundleId: "\(Sage.orgPrefix).AppTests",
    deploymentTargets: Sage.deployment,
    infoPlist: .default,
    sources: ["Projects/App/Tests/**"],
    dependencies: [
        .target(name: "Sage"),
        .module("CoreKit"), .module("SageTestSupport"), .module("VaultService"),
        .module("InferenceService"), .module("ModelService"),
        .module("SettingsStore"), .module("Localization"),
    ],
    settings: .settings(base: Sage.baseSettings)
)

// MARK: - App

let allFeatures: [TargetDependency] = [
    .module("AppShellFeature"),
    .module("OnboardingFeature"),
    .module("EditorFeature"),
    .module("ChatFeature"),
    .module("SearchFeature"),
    .module("SettingsFeature"),
]

let allServices: [TargetDependency] = [
    .module("SettingsStore"), .module("VaultService"), .module("MarkdownService"),
    .module("GitService"), .module("UpdateService"), .module("ModelService"), .module("InferenceService"),
    .module("SpeechService"), .module("ChatService"),
]

let swiftLintScript = """
export PATH="/opt/homebrew/bin:$HOME/.local/share/mise/shims:$PATH"
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet --config "$SRCROOT/.swiftlint.yml"
else
  echo "warning: SwiftLint не найден — пропускаю."
fi
"""

let app = Target.target(
    name: "Sage",
    destinations: Sage.destinations,
    product: .app,
    bundleId: "\(Sage.orgPrefix).app",
    deploymentTargets: Sage.deployment,
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Sage",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "LSMinimumSystemVersion": "15.0",
        "LSApplicationCategoryType": "public.app-category.productivity",
        "NSHumanReadableCopyright": "Sage — локальный ИИ-редактор заметок.",
        "NSMicrophoneUsageDescription": "Sage использует микрофон для голосового ввода: распознавание речи Whisper работает локально на вашем Mac.",
        "NSSupportsAutomaticTermination": true,
        "NSSupportsSuddenTermination": true,
    ]),
    sources: ["Projects/App/Sources/**"],
    resources: ["Projects/App/Resources/**"],
    scripts: [
        .pre(script: swiftLintScript, name: "SwiftLint", basedOnDependencyAnalysis: false),
    ],
    dependencies: allFeatures + allServices,
    settings: .settings(base: Sage.baseSettings.merging(["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"]) { _, new in new })
)

// MARK: - Project

let project = Project(
    name: "Sage",
    organizationName: "Sage",
    options: .options(
        automaticSchemesOptions: .enabled(),
        defaultKnownRegions: ["ru", "en", "zh-Hans"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: Sage.baseSettings,
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        coreKit, localization, designSystem,
        settingsStore, vaultService, markdownService, gitService, updateService,
        modelService, inferenceService, speechService, chatService,
        appShellFeature, onboardingFeature, editorFeature,
        chatFeature, searchFeature, settingsFeature,
        app,
        sageTestSupport,
        onboardingFeatureTests,
        coreKitTests, designSystemTests, localizationTests, vaultServiceTests, markdownServiceTests,
        modelServiceTests, settingsStoreTests, chatServiceTests, appShellFeatureTests,
        chatFeatureTests, editorFeatureTests, searchFeatureTests, gitServiceTests,
        updateServiceTests, settingsFeatureTests, appTests,
    ]
)
