import CoreKit
import DesignSystem
import Localization
import SwiftUI

/// Верхняя панель главной колонки (тоггл сайдбара, крошки, переключатели, тема, настройки).
public struct TitlebarView: View {
    private let crumbs: [String]
    private let hasNote: Bool
    private let vaultRoot: URL?
    private let fileURL: URL?

    @Bindable private var router: AppRouter
    private let theme: ThemeManager
    private let onCycleTheme: () -> Void

    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale
    @State private var crumbHover = false
    @State private var pathCopied = false

    public init(
        crumbs: [String], hasNote: Bool,
        vaultRoot: URL? = nil, fileURL: URL? = nil,
        router: AppRouter, theme: ThemeManager, onCycleTheme: @escaping () -> Void
    ) {
        self.crumbs = crumbs
        self.hasNote = hasNote
        self.vaultRoot = vaultRoot
        self.fileURL = fileURL
        self.router = router
        self.theme = theme
        self.onCycleTheme = onCycleTheme
    }

    private var s: Strings { locale.strings }

    public var body: some View {
        HStack(spacing: 10) {
            if !router.sidebarOpen {
                Color.clear.frame(width: 68, height: 1)
            }
            Button { router.toggleSidebar() } label: {
                Image(systemName: "sidebar.left").font(.system(size: 15)).foregroundStyle(palette.tx2)
            }
            .buttonStyle(.plain)
            .help("\(s.menu.toggleSidebar) ⌘S")

            breadcrumb

            Spacer(minLength: 0)

            if router.view == .editor, hasNote {
                SageSegmented(
                    [SegmentItem(tag: EditorVariant.a, label: "A"),
                     SegmentItem(tag: EditorVariant.b, label: "B")],
                    selection: $router.editorVariant,
                    accentSelected: true
                )
            }

            iconButton(symbol: themeIcon, action: onCycleTheme)
                .help(s.menu.cycleTheme)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.bd).frame(height: 1) }
    }

    /// Хлебные крошки полного пути: workspace / папка / … / подпапка / файл.
    /// Длинный путь сворачивается в «…» (по наведению — полный список свёрнутых папок).
    @ViewBuilder private var breadcrumb: some View {
        let items = collapsedCrumbs
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 { Text("/").foregroundStyle(palette.tx3) }
                let isLast = idx == items.count - 1
                Text(item.label)
                    .foregroundStyle(isLast ? palette.tx : palette.tx3)
                    .fontWeight(isLast ? .medium : .regular)
                    .lineLimit(1)
                    .help(item.tooltip ?? item.label)
            }
            if hasNote, fileURL != nil {
                copyPathButton
            }
        }
        .font(.sage(12.5))
        .onHover { crumbHover = $0 }
        .animation(.easeOut(duration: 0.14), value: crumbHover)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pathCopied)
    }

    @ViewBuilder private var copyPathButton: some View {
        Button(action: copyPath) {
            if pathCopied {
                HStack(spacing: 5) {
                    SageGlyphIcon(.check, size: 12, color: palette.ac)
                    Text(s.app.copied).font(.sage(11.5, .medium)).foregroundStyle(palette.ac)
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(palette.acs, in: RoundedRectangle(cornerRadius: Radius.xs))
            } else {
                SageGlyphIcon(.copy, size: 13, color: crumbHover ? palette.tx : palette.tx3)
                    .frame(width: 24, height: 24)
                    .background(crumbHover ? palette.bgh : .clear, in: RoundedRectangle(cornerRadius: Radius.xs))
            }
        }
        .buttonStyle(.plain)
        .help(s.app.copyPath)
    }

    private func copyPath() {
        guard let file = fileURL else { return }
        let rel = vaultRoot.map { file.relativePath(from: $0) } ?? file.lastPathComponent
        Pasteboard.copy("<\(rel)>")
        pathCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            pathCopied = false
        }
    }

    private struct Crumb { let label: String; let tooltip: String? }

    /// Если сегментов больше 4 — средние сворачиваются в «…» с тултипом всего пути.
    private var collapsedCrumbs: [Crumb] {
        let segs = crumbs
        guard segs.count > 4 else { return segs.map { Crumb(label: $0, tooltip: nil) } }
        let first = segs[0]
        let hidden = Array(segs[1 ..< (segs.count - 2)])
        let tail = Array(segs.suffix(2))
        return [Crumb(label: first, tooltip: nil),
                Crumb(label: "…", tooltip: hidden.joined(separator: " / "))]
            + tail.map { Crumb(label: $0, tooltip: nil) }
    }

    private var themeIcon: String {
        switch theme.mode {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .auto: "circle.lefthalf.filled"
        }
    }

    private func iconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.sage(14))
                .foregroundStyle(palette.tx2)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.bd, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.bgh)
    }
}
