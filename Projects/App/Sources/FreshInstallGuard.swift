import Foundation

/// НЕразрушающий маркер сборки. Раньше тут стирались настройки/модели/хранилище при
/// смене билда — из-за чего при переустановке пропадали скачанные модели и слетал онбординг.
/// Теперь состояние СОХРАНЯЕТСЯ между запусками и переустановками; полный сброс — только
/// вручную через `make reset` (defaults delete + удаление ~/Library/Application Support/Sage).
enum FreshInstallGuard {
    static func resetIfNewBuild() {
        let current = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        UserDefaults.standard.set(current, forKey: "sage.build")
    }
}
