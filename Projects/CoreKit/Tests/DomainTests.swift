import Foundation
import XCTest
@testable import CoreKit

final class ModelCatalogTests: XCTestCase {
    func testDefaultLLMIsQwen8B() {
        XCTAssertEqual(ModelCatalog.defaultLLM, "qwen3-8b")
        XCTAssertEqual(ModelCatalog.defaultWhisper, "base")
    }

    func testQwen8BIsRecommendedAndFirst() {
        XCTAssertEqual(ModelCatalog.llms.first?.id, "qwen3-8b")
        XCTAssertTrue(ModelCatalog.llm(id: "qwen3-8b")?.recommended == true)
    }

    func testGemmaAndQwen25Removed() {
        XCTAssertNil(ModelCatalog.llm(id: "gemma3-4b"))
        XCTAssertNil(ModelCatalog.llm(id: "qwen2.5-7b"))
        XCTAssertFalse(ModelCatalog.llms.contains { $0.id.hasPrefix("gemma") })
    }

    func testLookupHitMiss() {
        XCTAssertEqual(ModelCatalog.llm(id: "qwen3-4b")?.name, "Qwen3 4B")
        XCTAssertNil(ModelCatalog.llm(id: "nope"))
        XCTAssertEqual(ModelCatalog.whisper(id: "base")?.name, "Whisper Base")
    }

    func testExactlyOneRecommendedLLM() {
        XCTAssertEqual(ModelCatalog.llms.filter { $0.recommended }.count, 1)
    }
}

final class PromptTemplateTests: XCTestCase {
    func testGemma3Markers() {
        let p = PromptTemplate.gemma3.format(system: "SYS", user: "USR")
        XCTAssertTrue(p.contains("<start_of_turn>user"))
        XCTAssertTrue(p.contains("<start_of_turn>model"))
        XCTAssertTrue(p.contains("SYS"))
        XCTAssertTrue(p.contains("USR"))
    }

    func testChatMLMarkers() {
        let p = PromptTemplate.chatML.format(system: "SYS", user: "USR")
        XCTAssertTrue(p.contains("<|im_start|>system"))
        XCTAssertTrue(p.contains("<|im_start|>assistant"))
    }

    func testStopTokens() {
        XCTAssertEqual(PromptTemplate.gemma3.stopTokens, ["<end_of_turn>"])
        XCTAssertTrue(PromptTemplate.chatML.stopTokens.contains("<|im_end|>"))
    }
}

final class SidebarHighlightTests: XCTestCase {
    func testEditorViewHighlightsOpenFile() {
        XCTAssertEqual(sidebarHighlightID(view: .editor, chatContext: .vault, editorFile: "/v/a.md"), "/v/a.md")
        // даже если есть контекст чата — в режиме редактора светим открытый файл
        XCTAssertEqual(sidebarHighlightID(view: .editor, chatContext: .folder(name: "F", fileCount: 3, path: "/v/F"), editorFile: "/v/a.md"), "/v/a.md")
    }

    func testChatViewHighlightsContextNotEditorFile() {
        // в чате папки — светим ПАПКУ, а не открытый ранее файл (баг «рандомной» подсветки)
        XCTAssertEqual(sidebarHighlightID(view: .chat, chatContext: .folder(name: "F", fileCount: 3, path: "/v/F"), editorFile: "/v/old.md"), "/v/F")
        XCTAssertEqual(sidebarHighlightID(view: .chat, chatContext: .file(name: "a", path: "/v/a.md"), editorFile: "/v/old.md"), "/v/a.md")
    }

    func testChatVaultOrSelectionHighlightsNothing() {
        XCTAssertNil(sidebarHighlightID(view: .chat, chatContext: .vault, editorFile: "/v/old.md"))
        XCTAssertNil(sidebarHighlightID(view: .chat, chatContext: .selection(fileName: "a.md"), editorFile: "/v/old.md"))
    }
}

final class DownloadStateTests: XCTestCase {
    func testFractionClampsAndComputes() {
        XCTAssertEqual(DownloadProgress(downloadedBytes: 0, totalBytes: 0, speedBytesPerSec: 0).fraction, 0)
        XCTAssertEqual(DownloadProgress(downloadedBytes: 50, totalBytes: 100, speedBytesPerSec: 0).fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(DownloadProgress(downloadedBytes: 200, totalBytes: 100, speedBytesPerSec: 0).fraction, 1)
    }

    func testPercent() {
        XCTAssertEqual(DownloadProgress(downloadedBytes: 25, totalBytes: 100, speedBytesPerSec: 0).percent, 25)
    }

    func testStateFlags() {
        XCTAssertTrue(DownloadState.installed.isInstalled)
        XCTAssertTrue(DownloadState.verifying.isActive)
        XCTAssertTrue(DownloadState.downloading(.init(downloadedBytes: 0, totalBytes: 1, speedBytesPerSec: 0)).isActive)
        XCTAssertTrue(DownloadState.failed(message: "x").isFailed)
        XCTAssertFalse(DownloadState.notInstalled.isActive)
    }
}

final class FormattingTests: XCTestCase {
    func testSpeed() {
        XCTAssertEqual(Formatting.speed(bytesPerSec: 0, unit: "МБ/с"), "0.0 МБ/с")
        XCTAssertEqual(Formatting.speed(bytesPerSec: 0, unit: "MB/s"), "0.0 MB/s")
        XCTAssertTrue(Formatting.speed(bytesPerSec: 5 * 1024 * 1024, unit: "MB/s").contains("5.0"))
        XCTAssertTrue(Formatting.speed(bytesPerSec: 20 * 1024 * 1024, unit: "MB/s").contains("20"))
    }

    func testProgressComposesSizes() {
        let s = Formatting.progress(done: 1_000_000, total: 5_000_000)
        XCTAssertTrue(s.contains("/"))
    }

    func testRelativeTimeInjectedNow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let earlier = Date(timeIntervalSince1970: 10_000 - 3600)
        XCTAssertFalse(Formatting.relativeTime(earlier, now: now).isEmpty)
    }
}

final class FileNodeTests: XCTestCase {
    private func node(_ name: String, dir: Bool, _ children: [FileNode] = []) -> FileNode {
        FileNode(name: name, url: URL(fileURLWithPath: "/v/\(name)"), isDirectory: dir, depth: 0, children: children)
    }

    func testFlattenedCollapsed() {
        let root = node("root", dir: true, [node("a", dir: false), node("sub", dir: true, [node("b", dir: false)])])
        let flat = root.flattened(expanded: [])
        XCTAssertEqual(flat.map(\.name), ["root"])
    }

    func testFlattenedExpanded() {
        let sub = node("sub", dir: true, [node("b", dir: false)])
        let root = node("root", dir: true, [node("a", dir: false), sub])
        let flat = root.flattened(expanded: [root.id, sub.id])
        XCTAssertEqual(flat.map(\.name), ["root", "a", "sub", "b"])
    }
}

final class MiscDomainTests: XCTestCase {
    func testChatContextIcons() {
        XCTAssertEqual(ChatContext.vault.iconSymbol, "sparkles")
        XCTAssertEqual(ChatContext.file(name: "n", path: "p").iconSymbol, "doc.text")
        XCTAssertEqual(ChatContext.folder(name: "n", fileCount: 1, path: "p").iconSymbol, "folder")
    }

    func testNoteWordCount() {
        let d = NoteDocument(url: URL(fileURLWithPath: "/x.md"), text: "one two\nthree  four", modifiedAt: Date())
        XCTAssertEqual(d.wordCount, 4)
    }

    func testAppLanguageMappings() {
        XCTAssertEqual(AppLanguage.ru.flag.isEmpty, false)
        XCTAssertEqual(AppLanguage.allCases.count, 3)
        XCTAssertFalse(AppLanguage.en.nativeName.isEmpty)
    }
}
