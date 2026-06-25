import AppKit

/// Тонкая обёртка над системным буфером обмена (одна строка).
public enum Pasteboard {
    /// Заменить содержимое общего буфера обмена одной строкой.
    public static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
