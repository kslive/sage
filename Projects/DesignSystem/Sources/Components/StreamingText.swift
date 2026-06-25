import SwiftUI

/// Плавный «печатающий» вывод стрима ИИ: символы раскрываются равномерно (а не падают пачками
/// токенов), с мигающей кареткой во время генерации. Когда стрим закончился (`active=false`) И весь
/// текст дорисован — ОДИН раз вызывает `onComplete` (родитель свопает на форматированный markdown).
/// Важно: при `active=false` НЕ доскакивает мгновенно к концу — доезжает плавно (иначе анимации не видно).
public struct StreamingText: View {
    private let text: String
    private let active: Bool
    private let font: Font
    private let color: Color
    private let onComplete: () -> Void

    @State private var shown = 0
    @State private var frame = 0
    @State private var didComplete = false
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    public init(_ text: String, active: Bool = false, font: Font = .body, color: Color = .primary,
                onComplete: @escaping () -> Void = {}) {
        self.text = text
        self.active = active
        self.font = font
        self.color = color
        self.onComplete = onComplete
    }

    public var body: some View {
        let count = text.count
        let revealed = String(text.prefix(min(shown, count)))
        let caretOn = active && (frame / 32) % 2 == 0
        Text(revealed + (caretOn ? "▍" : ""))
            .font(font)
            .foregroundStyle(color)
            .animation(nil, value: shown)
            .onReceive(tick) { _ in
                guard active || shown < count || !didComplete else { return }
                if active { frame &+= 1 }
                if shown < count {
                    let step = max(2, (count - shown) / 10)
                    shown = min(count, shown + step)
                }
                if !active, shown >= count, !didComplete {
                    didComplete = true
                    onComplete()
                }
            }
            .onChange(of: text) { _, t in if shown > t.count { shown = t.count } }
            .onAppear {
                if !active { shown = text.count }
            }
    }
}
