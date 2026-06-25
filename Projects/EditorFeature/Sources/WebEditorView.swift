import AppKit
import DesignSystem
import SwiftUI
import WebKit

private final class EditorBundleToken {}

/// Контроллер веб-редактора: мост Swift → JS (команды) + кэш выделения.
@MainActor
public final class WebEditorController {
    fileprivate weak var webView: WKWebView?
    fileprivate var ready = false
    fileprivate var jsText = ""
    /// Поколение документа: растёт на setDoc/beginSwitch; «хвостовые» doc-сообщения старого
    /// поколения отбрасываются (анти-перезапись). Доступен на чтение тестам.
    public private(set) var epoch = 0
    public fileprivate(set) var selectedText = ""

    public init() {}

    private func run(_ js: String) {
        guard let webView, ready else { return }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private static func jsString(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let arr = String(data: data, encoding: .utf8) {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }

    func setDoc(_ text: String) {
        epoch += 1
        jsText = text
        run("window.sageSetDoc(\(Self.jsString(text)), \(epoch))")
    }

    /// Начало переключения файла: сразу поднимаем поколение, чтобы «хвостовые» doc-сообщения
    /// прошлого файла отбрасывались ещё до того, как загрузится новый документ (анти-перезапись).
    func beginSwitch() { epoch += 1 }
    func setMode(_ preview: Bool) { run("window.sageSetMode(\(preview ? "'preview'" : "'markdown'"))") }
    func setTheme(_ json: String) { run("window.sageSetTheme(\(Self.jsString(json)))") }
    /// Локализованные подписи слэш-меню (JSON ключ→текст из Strings.Slash). Иначе пункты по-русски.
    func setStrings(_ json: String) { run("window.sageSetStrings(\(Self.jsString(json)))") }
    public func scrollToHeading(_ text: String) { run("window.sageScrollToHeading(\(Self.jsString(text)))") }
    public func markSelection() { run("window.sageMarkSelection()") }
    public func clearMark() { run("window.sageClearMark()") }
    public func replaceSelection(_ text: String) { run("window.sageReplaceSelection(\(Self.jsString(text)))") }
    public func insertAtCursor(_ text: String) { run("window.sageInsertAtCursor(\(Self.jsString(text)))") }
    /// Вставить готовую строку (markdown-ссылка, собранная в Swift) — заменяет выделение/в курсор.
    public func insertText(_ text: String) { run("window.sageInsertText(\(Self.jsString(text)))") }
    public func insertImage(_ relPath: String) { run("window.sageInsertImage(\(Self.jsString(relPath)))") }
    /// Немедленно отправить документ из webview (минуя debounce) — для критичных правок.
    public func flushDoc() { run("window.sageFlushDoc()") }
    public func insertLink(title: String, path: String) {
        run("window.sageInsertLink(\(Self.jsString(title)), \(Self.jsString(path)))")
    }
    func setBaseFolder(_ path: String) { run("window.sageSetBase(\(Self.jsString(path)))") }
    public func focus() { run("window.sageFocus()") }
}

/// Отдаёт локальные картинки заметки в webview по схеме `sageimg://local/<percent-abs-path>`.
/// (index.html грузится из бандла, относительные `assets/...` иначе не резолвятся.)
final class SageImageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "sageimg"
    static let prefix = "sageimg://local/"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(NSError(domain: "sageimg", code: -1)); return
        }
        let s = url.absoluteString
        let encoded = s.hasPrefix(Self.prefix) ? String(s.dropFirst(Self.prefix.count)) : ""
        let path = encoded.removingPercentEncoding ?? encoded
        let fileURL = URL(fileURLWithPath: path)
        guard !path.isEmpty, let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(NSError(domain: "sageimg", code: 404)); return
        }
        let resp = URLResponse(url: url, mimeType: Self.mime(for: fileURL.pathExtension),
                               expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "svg": "image/svg+xml"
        case "heic": "image/heic"
        default: "application/octet-stream"
        }
    }
}

/// Markdown-редактор на CodeMirror 6 (Obsidian-style Live Preview) в WKWebView. Офлайн.
public struct WebEditorView: NSViewRepresentable {
    @Binding var text: String
    let previewMode: Bool
    let palette: ThemePalette
    let controller: WebEditorController
    let baseFolder: String?
    let onSelection: (String) -> Void
    let onOpenLink: (String) -> Void
    let onRequestAI: () -> Void
    let onRequestLink: (CGRect?) -> Void
    let onEscape: () -> Void
    let onSaveImage: (Data, String) async -> String?
    let onFlushDoc: () -> Void
    let onReady: () -> Void

    public init(text: Binding<String>, previewMode: Bool, palette: ThemePalette,
                controller: WebEditorController, baseFolder: String? = nil,
                onSelection: @escaping (String) -> Void = { _ in },
                onOpenLink: @escaping (String) -> Void = { _ in },
                onRequestAI: @escaping () -> Void = {},
                onRequestLink: @escaping (CGRect?) -> Void = { _ in },
                onEscape: @escaping () -> Void = {},
                onSaveImage: @escaping (Data, String) async -> String? = { _, _ in nil },
                onFlushDoc: @escaping () -> Void = {},
                onReady: @escaping () -> Void = {}) {
        _text = text
        self.previewMode = previewMode
        self.palette = palette
        self.controller = controller
        self.baseFolder = baseFolder
        self.onSelection = onSelection
        self.onOpenLink = onOpenLink
        self.onRequestAI = onRequestAI
        self.onRequestLink = onRequestLink
        self.onEscape = onEscape
        self.onSaveImage = onSaveImage
        self.onFlushDoc = onFlushDoc
        self.onReady = onReady
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func editorIndexURL() -> URL? {
        let bundle = Bundle(for: EditorBundleToken.self)
        if let u = bundle.url(forResource: "index", withExtension: "html", subdirectory: "editor") { return u }
        if let u = bundle.url(forResource: "index", withExtension: "html") { return u }
        if let nested = bundle.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
            for b in nested.compactMap({ Bundle(url: $0) }) {
                if let u = b.url(forResource: "index", withExtension: "html", subdirectory: "editor") { return u }
                if let u = b.url(forResource: "index", withExtension: "html") { return u }
            }
        }
        return nil
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sage")
        config.setURLSchemeHandler(SageImageSchemeHandler(), forURLScheme: SageImageSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        controller.webView = webView
        context.coordinator.controller = controller
        if let index = Self.editorIndexURL() {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard controller.ready else { return }
        if text != controller.jsText { controller.setDoc(text) }
        if context.coordinator.lastPreview != previewMode {
            context.coordinator.lastPreview = previewMode
            controller.setMode(previewMode)
        }
        let themeJSON = Self.themeJSON(palette)
        if context.coordinator.lastTheme != themeJSON {
            context.coordinator.lastTheme = themeJSON
            controller.setTheme(themeJSON)
        }
        let base = baseFolder ?? ""
        if context.coordinator.lastBase != base {
            context.coordinator.lastBase = base
            controller.setBaseFolder(base)
        }
    }

    static func themeJSON(_ p: ThemePalette) -> String {
        func hex(_ c: Color) -> String {
            let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
            return String(format: "rgba(%d,%d,%d,%.3f)",
                          Int(ns.redComponent * 255), Int(ns.greenComponent * 255),
                          Int(ns.blueComponent * 255), ns.alphaComponent)
        }
        let vars: [String: String] = [
            "--bg": hex(p.bg), "--bg1": hex(p.bg1), "--bg2": hex(p.bg2), "--bg3": hex(p.bg3),
            "--bd": hex(p.bd), "--bd2": hex(p.bd2), "--tx": hex(p.tx), "--tx2": hex(p.tx2),
            "--tx3": hex(p.tx3), "--ac": hex(p.ac), "--acs": hex(p.acs),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: vars),
           let s = String(data: data, encoding: .utf8) { return s }
        return "{}"
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WebEditorView
        weak var controller: WebEditorController?
        var lastPreview: Bool?
        var lastTheme: String?
        var lastBase: String?

        init(_ parent: WebEditorView) { self.parent = parent }

        /// Чистое решение по входящему `doc`-сообщению (для тестируемости без WKWebView).
        enum DocAction: Equatable {
            case ignore
            case apply(text: String, flush: Bool)
        }

        /// Принимаем правку ТОЛЬКО если поколение совпадает с текущим; иначе «хвост» прошлого файла.
        static func docAction(incomingEpoch: Int?, currentEpoch: Int, text: String?, flush: Bool) -> DocAction {
            guard let incomingEpoch, incomingEpoch == currentEpoch, let text else { return .ignore }
            return .apply(text: text, flush: flush)
        }

        /// Декод вставляемой картинки из тела сообщения: base64 → (Data, ext); невалидный b64 → nil.
        static func decodeImage(body: [String: Any]) -> (data: Data, ext: String)? {
            guard let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) else { return nil }
            let ext = (body["ext"] as? String) ?? "png"
            return (data, ext)
        }

        public func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                controller?.ready = true
                controller?.setDoc(parent.text)
                controller?.setMode(parent.previewMode)
                lastPreview = parent.previewMode
                let theme = WebEditorView.themeJSON(parent.palette)
                controller?.setTheme(theme); lastTheme = theme
                let base = parent.baseFolder ?? ""
                controller?.setBaseFolder(base); lastBase = base
                parent.onReady()
            case "doc":
                switch Self.docAction(incomingEpoch: body["epoch"] as? Int, currentEpoch: controller?.epoch ?? -1,
                                      text: body["text"] as? String, flush: (body["flush"] as? Bool) == true) {
                case .ignore: break
                case let .apply(text, flush):
                    controller?.jsText = text
                    if parent.text != text { parent.text = text }
                    if flush { parent.onFlushDoc() }
                }
            case "selection":
                let sel = (body["text"] as? String) ?? ""
                controller?.selectedText = sel
                parent.onSelection(sel)
            case "openLink":
                if let href = body["href"] as? String { parent.onOpenLink(href) }
            case "requestAI":
                if let sel = body["selection"] as? String { controller?.selectedText = sel }
                parent.onRequestAI()
            case "requestLink":
                var rect: CGRect?
                if let r = body["rect"] as? [String: Any],
                   let left = r["left"] as? Double, let top = r["top"] as? Double, let bottom = r["bottom"] as? Double {
                    rect = CGRect(x: left, y: top, width: 1, height: max(1, bottom - top))
                }
                parent.onRequestLink(rect)
            case "escape":
                parent.onEscape()
            case "insertImage":
                guard let img = Self.decodeImage(body: body) else { break }
                let save = parent.onSaveImage
                let ctrl = controller
                Task { @MainActor in
                    if let rel = await save(img.data, img.ext) { ctrl?.insertImage(rel); ctrl?.flushDoc() }
                }
            default: break
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let controller = self.controller, !controller.ready else { return }
                controller.ready = true
                controller.setDoc(self.parent.text)
                controller.setMode(self.parent.previewMode)
                controller.setTheme(WebEditorView.themeJSON(self.parent.palette))
                self.parent.onReady()
            }
        }
    }
}
