import CoreKit
import DesignSystem
import SwiftUI

/// Одноразовый анонс после обновления: нотсы GitHub-релиза версии, на которую пользователь
/// только что обновился, на языке приложения. Модально поверх всего окна.
struct WhatsNewOverlay: View {
    let version: String
    let blocks: [MarkdownBlock]
    let title: String
    let okLabel: String
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var notesHeight: CGFloat = 0

    /// Кап высоты блока нотсов: выше — включается скролл.
    private let notesCap: CGFloat = 380

    var body: some View {
        ZStack {
            Color.black.opacity(palette.isDark ? 0.5 : 0.3)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            card
        }
        .background {
            Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0)
        }
    }

    /// Тело нотсов: пока влезает под кап — карта обнимает контент, иначе появляется скролл.
    private var notes: some View {
        MarkdownBlocksView(blocks)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                SparkMark(size: 19, color: palette.ac)
                    .frame(width: 40, height: 40)
                    .background(palette.acs, in: RoundedRectangle(cornerRadius: 11))
                Text("\(title) \(version)")
                    .font(.sage(17, .semibold)).tracking(-0.2)
                    .foregroundStyle(palette.tx)
                Spacer(minLength: 0)
            }
            .padding(24)

            /// Высота = реальная высота контента (текст прибит к верху, без пустот),
            /// но не выше капа — тогда работает скролл. ViewThatFits не подходит:
            /// он жадно забирает всю предложенную высоту и центрирует контент.
            ScrollView {
                notes.background(
                    GeometryReader { g in
                        Color.clear.preference(key: NotesHeightKey.self, value: g.size.height)
                    }
                )
            }
            .onPreferenceChange(NotesHeightKey.self) { notesHeight = $0 }
            .frame(height: min(max(notesHeight, 60), notesCap))
            .scrollIndicators(notesHeight > notesCap ? .automatic : .never)

            Rectangle().fill(palette.bd).frame(height: 1)
            HStack {
                Spacer()
                SageButton(okLabel, kind: .primary, action: onClose)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 560)
        .background(palette.bg2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.bd, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 70, x: 0, y: 30)
    }
}

/// Реальная высота контента нотсов (для «карта обнимает текст, скролл только выше капа»).
private struct NotesHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
