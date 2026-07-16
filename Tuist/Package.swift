// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Внешние SPM-продукты собираются как ДИНАМИЧЕСКИЕ фреймворки — их символы линкуются один раз.
        productTypes: [
            "SwiftWhisper": .framework,
            // MLX (Apple-нативный инференс). MLXNN (+ остальные mlx-модули) ОБЯЗАНЫ быть общими
            // динамическими фреймворками: иначе MLXNN статически вшивается и в MLXLLM, и в
            // MLXLMCommon → два разных типа `Linear`/`QuantizedLinear` → краш квантизации
            // `unableToCast("Linear")` в Release.
            "MLXLLM": .framework,
            "MLXLMCommon": .framework,
            "MLX": .framework,
            "MLXNN": .framework,
            "MLXRandom": .framework,
            "MLXFast": .framework,
            "MLXFFT": .framework,
            "MLXLinalg": .framework,
            "MLXOptimizers": .framework,
            // swift-transformers + Jinja — общие динамические: иначе Tokenizers/Hub вшиваются
            // статически в несколько модулей → дубли Obj-C классов и загадочные краши.
            "Transformers": .framework,
            "Tokenizers": .framework,
            "Hub": .framework,
            "Generation": .framework,
            "Models": .framework,
            "TensorUtils": .framework,
            "Jinja": .framework,
        ],
        baseSettings: .settings(),
        // Cmlx наследует platforms mlx-swift (13.3) → Metal language 3.0 → нет типа `bfloat` →
        // шейдеры не собираются. Поднимаем deployment таргета до минимума приложения (Metal 3.2).
        targetSettings: [
            "Cmlx": .settings(base: ["MACOSX_DEPLOYMENT_TARGET": "15.0"]),
        ]
    )
#endif

let package = Package(
    name: "SageDeps",
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper", branch: "master"),
        // MLX-инференс, стек 3.x (KV-квантизация без ротационного кэша, DWQ-модели, новый generate-API).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.4"),
        // Hub-загрузка моделей (HubApi.snapshot): mlx-swift-lm 3.x выбросил встроенный hub-клиент,
        // скачивание Sage остаётся на swift-transformers (диск-поллинг прогресса, offline-ретрай).
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "0.1.24"),
    ]
)
