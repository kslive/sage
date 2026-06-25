import CoreKit
import DesignSystem
import Localization
import SwiftUI

public struct SearchView: View {
    @State private var vm: SearchViewModel
    private let onClose: () -> Void
    private let onOpen: (URL) -> Void
    private let onAsk: (String) -> Void

    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale
    @FocusState private var focused: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var selectedIndex = 0

    public init(
        vault: VaultServicing, markdown: MarkdownRendering, rootURL: URL?,
        onClose: @escaping () -> Void, onOpen: @escaping (URL) -> Void, onAsk: @escaping (String) -> Void
    ) {
        _vm = State(wrappedValue: SearchViewModel(vault: vault, markdown: markdown, rootURL: rootURL))
        self.onClose = onClose
        self.onOpen = onOpen
        self.onAsk = onAsk
    }

    private var s: Strings { locale.strings }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { onClose() }
            panel
                .frame(width: 600)
                .padding(.top, 90)
        }
        .onExitCommand { onClose() }
        .task {
            await vm.loadRecent()
            focused = true
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(palette.tx3)
                TextField("", text: $vm.query)
                    .textFieldStyle(.plain).font(.sage(16)).foregroundStyle(palette.tx)
                    .sagePlaceholder(s.search.placeholder, when: vm.query.isEmpty)
                    .focused($focused)
                    .onChange(of: vm.query) { _, _ in selectedIndex = 0; vm.onQueryChange() }
                    .onMoveCommand { direction in handleMove(direction) }
                    .onKeyPress(.upArrow) { handleMove(.up); return .handled }
                    .onKeyPress(.downArrow) { handleMove(.down); return .handled }
                    .onSubmit { submitSelection() }
                Text("ESC").font(.sage(11)).foregroundStyle(palette.tx3)
                    .padding(.vertical, 2).padding(.horizontal, 7)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.bd, lineWidth: 1))
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.bd).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(heading).sageType(.caption).foregroundStyle(palette.tx3)
                        if vm.loading { SageSpinner(size: 12) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)

                    if vm.loading {
                        ForEach(0 ..< 4, id: \.self) { _ in skeletonRow }
                    } else if vm.isEmpty {
                        Text(s.search.noResults).font(.sage(13)).foregroundStyle(palette.tx3)
                            .frame(maxWidth: .infinity).padding(26)
                    } else {
                        ForEach(Array(displayedResults.enumerated()), id: \.element.id) { idx, result in
                            resultRow(result, selected: idx == selectedIndex)
                        }
                    }

                    Rectangle().fill(palette.bd).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 4)
                    askRow
                }
                .padding(7)
                .background(GeometryReader { g in
                    Color.clear.preference(key: SearchContentHeightKey.self, value: g.size.height)
                })
            }
            .frame(height: min(contentHeight, 420))
            .onPreferenceChange(SearchContentHeightKey.self) { contentHeight = $0 }
        }
        .background(palette.bg2, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.bd2, lineWidth: 1))
        .sageElevation(palette)
    }

    private var heading: String {
        vm.query.isEmpty ? s.search.recent.uppercased() : (vm.loading ? s.search.searching.uppercased() : s.search.results.uppercased())
    }

    private var displayedResults: [SearchResult] {
        vm.query.isEmpty ? vm.recent : vm.results
    }

    private var askIndex: Int { displayedResults.count }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .down: selectedIndex = min(selectedIndex + 1, askIndex)
        case .up: selectedIndex = max(selectedIndex - 1, 0)
        default: break
        }
    }

    private func submitSelection() {
        if selectedIndex < displayedResults.count, let url = displayedResults[selectedIndex].fileURL {
            onOpen(url)
        } else {
            onAsk(vm.query)
        }
    }

    private func resultRow(_ result: SearchResult, selected: Bool) -> some View {
        Button { if let url = result.fileURL { onOpen(url) } } label: {
            HStack(spacing: 13) {
                Image(systemName: result.icon).font(.system(size: 15)).foregroundStyle(palette.tx2).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title).font(.sage(13.5, .medium)).foregroundStyle(palette.tx).lineLimit(1)
                    if !result.snippet.isEmpty {
                        Text(result.snippet).font(.sage(12)).foregroundStyle(palette.tx3).lineLimit(1)
                    }
                }
                Spacer()
                Text(result.path).font(.sage(11.5)).foregroundStyle(palette.tx3)
                    .padding(.vertical, 2).padding(.horizontal, 8)
                    .background(palette.bg3, in: RoundedRectangle(cornerRadius: Radius.xs))
            }
            .padding(.horizontal, 11).padding(.vertical, 11).contentShape(Rectangle())
            .background(selected ? palette.bgh : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.bgh, radius: Radius.md)
    }

    private var skeletonRow: some View {
        HStack(spacing: 13) {
            SkeletonBar(width: 18, height: 18, animated: false)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 200, height: 9)
                SkeletonBar(width: 320, height: 8, animated: false)
            }
            Spacer()
        }
        .padding(11)
    }

    private var askRow: some View {
        Button { onAsk(vm.query) } label: {
            HStack(spacing: 13) {
                SparkMark(size: 15, color: palette.ac).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(askLabel).font(.sage(13.5, .medium)).foregroundStyle(palette.ac)
                    if !vm.query.isEmpty {
                        Text(s.search.askSub).font(.sage(12)).foregroundStyle(palette.tx3)
                    }
                }
                Spacer()
                Text("↵").font(.sage(11)).foregroundStyle(palette.tx3)
                    .padding(.vertical, 2).padding(.horizontal, 7)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.bd, lineWidth: 1))
            }
            .padding(11).contentShape(Rectangle())
            .background(selectedIndex == askIndex ? palette.acs : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.acs, radius: Radius.md)
    }

    private var askLabel: String {
        vm.query.isEmpty ? s.search.askSub : "\(s.search.askPrefix): «\(vm.query)»"
    }
}

private struct SearchContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
