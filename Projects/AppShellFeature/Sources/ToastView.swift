import CoreKit
import DesignSystem
import SwiftUI

/// Всплывающее уведомление (внизу справа).
public struct ToastView: View {
    private let toast: Toast
    private let onAction: (() -> Void)?
    @Environment(\.palette) private var palette

    public init(_ toast: Toast, onAction: (() -> Void)? = nil) {
        self.toast = toast
        self.onAction = onAction
    }

    public var body: some View {
        Group {
            if toast.action != nil {
                actionCard
            } else {
                simpleToast
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .sageElevation(palette)
    }

    /// Простой тост: иконка-emoji + текст (одна строка).
    private var simpleToast: some View {
        HStack(spacing: 11) {
            Text(toast.icon).font(.sage(15)).foregroundStyle(iconColor)
            Text(toast.text).sageType(.ui).foregroundStyle(palette.tx)
        }
        .padding(.vertical, 13).padding(.horizontal, 17)
    }

    /// Actionable-карта (Секция 05d): искра-в-кружке с кольцом rglow + заголовок + mono-путь + «Открыть» + ×.
    private var actionCard: some View {
        HStack(spacing: 12) {
            GlowRing(size: 26, sparkSize: 14, corner: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.text).font(.sage(12.5, .semibold)).foregroundStyle(palette.tx)
                if let subtitle = toast.subtitle {
                    Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.tx3)
                }
            }
            if let action = toast.action, let onAction {
                Button(action: onAction) {
                    Text(action.label).font(.sage(12, .semibold)).foregroundStyle(palette.onAccent)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(palette.ac, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 11).padding(.leading, 15).padding(.trailing, 13)
    }

    private var iconColor: Color {
        switch toast.kind {
        case .success: palette.ac
        case .error: palette.error
        case .info: palette.tx2
        }
    }

    private var borderColor: Color {
        if toast.action != nil, toast.kind == .success { return palette.ac.opacity(0.32) }
        switch toast.kind {
        case .success: return palette.bd
        case .error: return palette.error.opacity(0.4)
        case .info: return palette.bd
        }
    }
}

/// Хост тостов: размещает текущий тост в правом нижнем углу. Кликабелен только тост с действием.
public struct ToastHost: View {
    private let center: ToastCenter
    private let onAction: (AITaskRoute) -> Void

    public init(_ center: ToastCenter, onAction: @escaping (AITaskRoute) -> Void = { _ in }) {
        self.center = center
        self.onAction = onAction
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear.allowsHitTesting(false)
            if let toast = center.current {
                ToastView(toast, onAction: toast.action.map { act in { onAction(act.route); center.dismiss() } })
                    .padding(24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .id(toast.id)
                    .allowsHitTesting(toast.action != nil)
            }
        }
        .animation(SageMotion.pop, value: center.current?.id)
    }
}
