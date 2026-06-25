import Foundation

/// Режим темы. `auto` следует системной настройке.
public enum AppTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case dark
    case light
    case auto

    public var id: String { rawValue }
}

/// Пресет акцентного цвета (значения для тёмной и светлой темы).
public struct AccentPreset: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let darkHex: String
    public let lightHex: String

    public init(id: String, darkHex: String, lightHex: String) {
        self.id = id
        self.darkHex = darkHex
        self.lightHex = lightHex
    }

    public static let green = AccentPreset(id: "green", darkHex: "#4CC38A", lightHex: "#16895A")
    public static let blue = AccentPreset(id: "blue", darkHex: "#5B8DEF", lightHex: "#2563C7")
    public static let sand = AccentPreset(id: "sand", darkHex: "#C9986A", lightHex: "#9C6B3C")
    public static let purple = AccentPreset(id: "purple", darkHex: "#B06AD6", lightHex: "#7C3FB0")
    public static let coral = AccentPreset(id: "coral", darkHex: "#E0707A", lightHex: "#C2434F")

    /// Свотчи акцента (как в макете — раздел «Оформление»).
    public static let all: [AccentPreset] = [.green, .blue, .sand, .purple, .coral]

    public static func preset(id: String) -> AccentPreset {
        all.first { $0.id == id } ?? .green
    }
}
