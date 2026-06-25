import CoreKit
import DesignSystem
import SwiftUI

/// Голосовой ввод в стиле ChatGPT (макет Секция 07): орб с дыханием + расходящиеся кольца + волны по
/// амплитуде, таймер записи mm:ss, кнопки × отменить / ✓ остановить-и-распознать. Поверх приглушённого чата.
struct VoiceOrbOverlay: View {
    let phase: VoicePhase
    let levels: [Float]
    let recordingStart: Date?
    let title: String
    let hint: String
    let cancelLabel: String
    let confirmLabel: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.palette) private var palette
    @State private var ringExpand = false
    @State private var orbBreathe = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [palette.bg.opacity(0.96), palette.bg.opacity(0.99)],
                                     startPoint: .top, endPoint: .bottom))
                .contentShape(Rectangle())

            VStack(spacing: 0) {
                orb.padding(.bottom, 24)

                Text(title)
                    .sageType(.h2)
                    .foregroundStyle(palette.tx)

                if phase != .transcribing {
                    Text(hint)
                        .font(.sage(13)).foregroundStyle(palette.tx2)
                        .multilineTextAlignment(.center).frame(maxWidth: 280).lineSpacing(2)
                        .padding(.top, 7).padding(.bottom, 8)
                    timer.padding(.bottom, 26)

                    HStack(spacing: 16) {
                        VoiceCircleButton(system: "xmark", filled: false, size: 50, action: onCancel)
                            .keyboardShortcut(.cancelAction)
                            .help(cancelLabel)
                        VoiceCircleButton(system: "checkmark", filled: true, size: 62, action: onConfirm)
                            .keyboardShortcut(.return, modifiers: [])
                            .help(confirmLabel)
                    }

                    Text("✕ \(cancelLabel) · ✓ \(confirmLabel)")
                        .font(.sage(11)).foregroundStyle(palette.tx3)
                        .padding(.top, 16)
                }
            }
        }
        .transition(.opacity)
        .onAppear { ringExpand = true; orbBreathe = true }
    }

    // MARK: - Орб

    private var orb: some View {
        ZStack {
            ForEach(0 ..< 2, id: \.self) { i in
                Circle().strokeBorder(palette.ac.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 144, height: 144)
                    .scaleEffect(ringExpand ? 1.6 : 0.85)
                    .opacity(ringExpand ? 0 : 0.7)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)
                        .delay(Double(i) * 1.2), value: ringExpand)
            }
            Circle()
                .fill(palette.ac)
                .frame(width: 120, height: 120)
                .overlay(
                    RadialGradient(colors: [Color.white.opacity(0.5), .clear],
                                   center: UnitPoint(x: 0.36, y: 0.30), startRadius: 2, endRadius: 56)
                        .clipShape(Circle())
                )
                .shadow(color: palette.ac.opacity(0.55), radius: 30)
                .scaleEffect(orbBreathe ? 1.08 : 1)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: orbBreathe)
                .overlay { if phase == .listening { bars } else { SageSpinner(size: 26, color: palette.onAccent) } }
        }
        .frame(width: 172, height: 172)
    }

    /// 7 волн по амплитуде (waveLevels) — контрастный onAccent поверх акцентной орбы (любой акцент/тема).
    private var bars: some View {
        HStack(spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, lvl in
                Capsule().fill(palette.onAccent)
                    .frame(width: 4, height: max(8, CGFloat(lvl) * 46))
                    .animation(.easeInOut(duration: 0.18), value: lvl)
            }
        }
        .frame(height: 46)
    }

    // MARK: - Таймер mm:ss (через TimelineView от recordingStart)

    @ViewBuilder private var timer: some View {
        if let start = recordingStart {
            TimelineView(.periodic(from: start, by: 1)) { ctx in
                Text(Formatting.elapsedClock(Int(ctx.date.timeIntervalSince(start))))
                    .font(.sage(12, .semibold)).monospacedDigit().foregroundStyle(palette.ac)
            }
        } else {
            Text("0:00").font(.sage(12, .semibold)).monospacedDigit().foregroundStyle(palette.ac)
        }
    }
}

/// Круглая кнопка голосового оверлея (× контурная / ✓ акцентная) с подсветкой при наведении.
private struct VoiceCircleButton: View {
    let system: String
    let filled: Bool
    let size: CGFloat
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: filled ? 20 : 17, weight: filled ? .bold : .medium))
                .foregroundStyle(filled ? palette.onAccent : (hovering ? palette.tx : palette.tx2))
                .frame(width: size, height: size)
                .background {
                    if filled {
                        Circle().fill(palette.ac)
                    } else {
                        Circle().fill(hovering ? palette.bgh : .clear)
                            .overlay(Circle().strokeBorder(hovering ? palette.bd2 : palette.bd, lineWidth: 1))
                    }
                }
                .shadow(color: filled ? palette.ac.opacity(hovering ? 0.6 : 0.4) : .clear,
                        radius: filled ? 14 : 0, y: filled ? 6 : 0)
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(SageMotion.quick, value: hovering)
    }
}
