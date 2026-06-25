// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [
            "SwiftWhisper": .framework,
            // MLX (Apple-нативный инференс) + swift-transformers (Hub-загрузка моделей)
            "MLXLLM": .framework,
            "MLXLMCommon": .framework,
            "MLXHuggingFace": .framework,
            "MLX": .framework,
            "MLXNN": .framework,
            "MLXRandom": .framework,
            "MLXFast": .framework,
            "Transformers": .framework,
            "Hub": .framework,
            "HuggingFace": .framework,
        ]
    )
#endif

let package = Package(
    name: "SageDeps",
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper", branch: "master"),
        // MLX-инференс (стабильный тег): MLXLLM + авто-загрузка по id, поддержка qwen3.
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.25.5"),
    ]
)
