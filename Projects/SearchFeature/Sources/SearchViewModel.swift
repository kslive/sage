import CoreKit
import Foundation
import Observation

@MainActor
@Observable
public final class SearchViewModel {
    public var query = ""
    public var loading = false
    public var results: [SearchResult] = []
    public var recent: [SearchResult] = []

    private let vault: VaultServicing
    private let markdown: MarkdownRendering
    private let rootURL: URL?
    private var searchTask: Task<Void, Never>?

    public init(vault: VaultServicing, markdown: MarkdownRendering, rootURL: URL?) {
        self.vault = vault
        self.markdown = markdown
        self.rootURL = rootURL
    }

    public var isEmpty: Bool { !query.isEmpty && results.isEmpty && !loading }

    public func loadRecent() async {
        guard let root = rootURL else { return }
        let files = await vault.allMarkdownFiles(under: root).prefix(6)
        recent = files.map { url in
            SearchResult(
                id: url.path, title: url.deletingPathExtension().lastPathComponent,
                path: relativePath(url, root: root), snippet: "", icon: "doc.text", fileURL: url
            )
        }
    }

    public func onQueryChange() {
        searchTask?.cancel()
        let q = query.normalizedSearchKey
        guard !q.isEmpty else { results = []; loading = false; return }
        loading = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performSearch(q)
        }
    }

    private func performSearch(_ q: String) async {
        guard let root = rootURL else { loading = false; return }
        let files = await vault.allMarkdownFiles(under: root)
        var found: [SearchResult] = []
        for url in files {
            guard let doc = try? await vault.readNote(at: url) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            let plain = markdown.plainText(doc.text)
            let titleHit = title.lowercased().contains(q)
            if let range = plain.lowercased().range(of: q) {
                found.append(SearchResult(
                    id: url.path, title: title, path: relativePath(url, root: root),
                    snippet: snippet(plain, around: range), icon: "doc.text", fileURL: url
                ))
            } else if titleHit {
                found.append(SearchResult(
                    id: url.path, title: title, path: relativePath(url, root: root),
                    snippet: String(plain.prefix(80)), icon: "doc.text", fileURL: url
                ))
            }
            if found.count >= 20 { break }
        }
        guard !Task.isCancelled else { return }
        results = found
        loading = false
    }

    private func snippet(_ text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + text[start ..< end].trimmingCharacters(in: .whitespaces) + "…"
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let rel = url.deletingLastPathComponent().path.replacingOccurrences(of: root.path, with: "")
        return rel.isEmpty ? "/" : rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
