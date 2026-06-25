import Foundation

/// Потоковый фильтр вывода LLM: срезает ведущий блок `<think>…</think>` (от `/no_think` он пустой)
/// И ведущие переносы/пробелы ДО первого реального контента — иначе ответ начинается с пустой
/// строки (лишний отступ сверху). Внутренние пробелы и пробелы после старта контента сохраняются.
///
/// Состояние копится между чанками: `push` вызывают на каждый кусок токенайзера; возвращаемое
/// значение нужно выдавать (`nil` → пока ничего не выдаём, ждём следующий чанк).
public struct ThinkStripper {
    private var raw = ""
    private var pastThink = false
    private var started = false

    public init() {}

    private static func isWS(_ c: Character) -> Bool { c == " " || c == "\n" || c == "\r" || c == "\t" }

    /// Подать следующий кусок. Возвращает текст для выдачи или `nil`, если пока выдавать нечего.
    /// Никогда не возвращает пустую строку (либо `nil`, либо непустой фрагмент).
    public mutating func push(_ piece: String) -> String? {
        if piece.isEmpty { return nil }
        if pastThink {
            var p = Substring(piece)
            if !started {
                p = p.drop(while: Self.isWS)
                if p.isEmpty { return nil }
                started = true
            }
            return String(p)
        }
        raw += piece
        let trimmed = raw.drop(while: Self.isWS)
        if trimmed.hasPrefix("<think>") {
            if let r = raw.range(of: "</think>") {
                let after = raw[r.upperBound...].drop(while: Self.isWS)
                pastThink = true
                if !after.isEmpty { started = true; return String(after) }
            }
            return nil
        } else if "<think>".hasPrefix(trimmed) {
            return nil
        } else {
            pastThink = true
            if !trimmed.isEmpty { started = true; return String(trimmed) }
            return nil
        }
    }
}
