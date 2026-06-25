import AppKit
import SwiftUI

/// Перетаскиваемый вертикальный разделитель для изменения ширины панели (с клампом).
public struct ResizeHandle: View {
    @Binding private var width: CGFloat
    private let minWidth: CGFloat
    private let maxWidth: CGFloat
    private let invert: Bool
    @State private var start: CGFloat?
    @State private var hovering = false

    /// `invert: true` — для ручки на ЛЕВОЙ грани панели (тянем вправо → панель уже).
    public init(width: Binding<CGFloat>, min: CGFloat, max: CGFloat, invert: Bool = false) {
        _width = width
        minWidth = min
        maxWidth = max
        self.invert = invert
    }

    public var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if start == nil { start = width }
                        let base = start ?? width
                        let raw = value.location.x - value.startLocation.x
                        let delta = invert ? -raw : raw
                        width = Swift.min(Swift.max(base + delta, minWidth), maxWidth)
                    }
                    .onEnded { _ in start = nil }
            )
    }
}
