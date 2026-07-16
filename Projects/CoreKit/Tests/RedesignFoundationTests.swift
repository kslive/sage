import Foundation
import XCTest
@testable import CoreKit

final class RedesignFoundationTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/V")

    private func file(_ rel: String, _ mod: Date? = nil) -> FileNode {
        FileNode(name: (rel as NSString).lastPathComponent, url: root.appendingPathComponent(rel),
                 isDirectory: false, depth: 2, modifiedAt: mod)
    }
    private func dir(_ rel: String, _ kids: [FileNode]) -> FileNode {
        FileNode(name: (rel as NSString).lastPathComponent, url: root.appendingPathComponent(rel, isDirectory: true),
                 isDirectory: true, depth: 1, children: kids)
    }

    // MARK: - Formatting.dateContext (ИИ понимает даты)

    func testDateContextHasTodayAndYesterday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = Date(timeIntervalSince1970: 1_750_000_000)   // фиксированная дата
        let line = Formatting.dateContext(now: now, calendar: cal)
        let iso = DateFormatter(); iso.calendar = cal; iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"; iso.timeZone = cal.timeZone
        let today = iso.string(from: now)
        let yest = iso.string(from: cal.date(byAdding: .day, value: -1, to: now) ?? now)
        XCTAssertTrue(line.contains(today), "должна быть сегодняшняя дата \(today)")
        XCTAssertTrue(line.contains(yest), "должна быть вчерашняя дата \(yest)")
    }

    // MARK: - InferenceLimits (модель-зависимый контекст)

    func testInferenceLimitsCapsPromptBudget() {
        let l16 = InferenceLimits(contextSize: 16384)
        XCTAssertEqual(l16.context, 16384)
        XCTAssertEqual(l16.promptBudget, 12000)              // кап 12k: жирный prefill лагает весь Mac
        let l40 = InferenceLimits(contextSize: 40960)
        XCTAssertEqual(l40.context, 40960)
        XCTAssertEqual(l40.promptBudget, 12000)
        let l8 = InferenceLimits(contextSize: 8192)
        XCTAssertEqual(l8.promptBudget, 8192 - 1024 - 1200)  // ниже капа — по формуле
    }

    func testInferenceLimitsFloor() {
        XCTAssertEqual(InferenceLimits(contextSize: 1000).context, 2048)   // флор
        XCTAssertEqual(InferenceLimits(contextSize: 1000).promptBudget, 2000)
    }

    func testCatalogContextPerModel() {
        func ctx(_ id: String) -> Int? { ModelCatalog.llms.first { $0.id == id }?.contextSize }
        for spec in ModelCatalog.llms {
            XCTAssertEqual(spec.contextSize, 40960, "\(spec.id): Qwen3 нативно держит 40960 (бюджет промпта капается отдельно)")
        }
        XCTAssertNotNil(ctx("qwen3-4b-2507"), "DWQ/Instruct-карточка в каталоге")
        XCTAssertNotNil(ctx("qwen3-8b"), "классические репо сохранены — скачанное не превращается в ре-даунлод")
        XCTAssertEqual(ModelCatalog.defaultLLM, "qwen3-4b-2507")
        XCTAssertEqual(ModelCatalog.llms.filter(\.recommended).count, 1)
    }

    // MARK: - FileNode.mdCount (рекурсивно)

    func testMdCountRecursive() {
        let node = dir("Reference", [
            file("Reference/a.md"), file("Reference/b.md"),
            dir("Reference/Sub", [file("Reference/Sub/c.md"), file("Reference/Sub/d.md")]),
        ])
        XCTAssertEqual(node.mdCount, 4)             // 2 прямых + 2 вложенных
        XCTAssertEqual(dir("Empty", []).mdCount, 0)
    }

    // MARK: - Сайдбар: предки для раскрытия (хайлайт без прыжка) + резерв слота статуса

    func testSidebarAncestorFolderIDs() {
        let leaf = file("Reference/Sub/c.md")
        let sub = dir("Reference/Sub", [leaf])
        let ref = dir("Reference", [sub])
        let tree = [ref, dir("Other", [file("Other/x.md")])]
        // оба предка вложенного файла → их раскрываем, чтобы узел стал виден (хайлайт/скролл попадают)
        XCTAssertEqual(Set(sidebarAncestorFolderIDs(of: leaf.id, in: tree)), [ref.id, sub.id])
        // узел верхнего уровня → предков нет (no-op, нет «прыжка»)
        XCTAssertTrue(sidebarAncestorFolderIDs(of: ref.id, in: tree).isEmpty)
        // отсутствующий id → пусто
        XCTAssertTrue(sidebarAncestorFolderIDs(of: "/nope", in: tree).isEmpty)
    }

    func testSidebarReservesStatusSlot() {
        XCTAssertTrue(sidebarReservesStatusSlot(hasTask: true, isDirectory: false, mdCount: 0))    // файл с задачей
        XCTAssertTrue(sidebarReservesStatusSlot(hasTask: false, isDirectory: true, mdCount: 3))    // папка со счётчиком
        XCTAssertFalse(sidebarReservesStatusSlot(hasTask: false, isDirectory: false, mdCount: 0))  // файл без задачи → имя не теряет ширину
        XCTAssertFalse(sidebarReservesStatusSlot(hasTask: false, isDirectory: true, mdCount: 0))   // пустая папка
    }

    func testSidebarShowsHoverAsk() {
        // hover без активной задачи → показываем ✦-«спросить»
        XCTAssertTrue(sidebarShowsHoverAsk(hovering: true, isRenaming: false, hasTask: false))
        // ЕСТЬ задача (running/готово) → ✦ НЕ показываем: индикатор задачи остаётся кликабельным (инлайн-ответ),
        // иначе клик уводил в чат вместо возврата к ответу
        XCTAssertFalse(sidebarShowsHoverAsk(hovering: true, isRenaming: false, hasTask: true))
        XCTAssertFalse(sidebarShowsHoverAsk(hovering: false, isRenaming: false, hasTask: false))   // нет наведения
        XCTAssertFalse(sidebarShowsHoverAsk(hovering: true, isRenaming: true, hasTask: false))     // идёт переименование
    }

    // MARK: - FileNode.sortedChildren

    func testSortByNameDirsFirst() {
        let node = dir("R", [file("zebra.md"), dir("R/Beta", []), file("alpha.md"), dir("R/Alpha", [])])
        let sorted = node.sortedChildren(by: .name).map(\.name)
        XCTAssertEqual(sorted, ["Alpha", "Beta", "alpha.md", "zebra.md"])  // папки А–Я, затем файлы А–Я
    }

    func testSortByModifiedNewestFirst() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        let t2 = Date(timeIntervalSince1970: 3000)
        let node = dir("R", [file("old.md", t0), file("new.md", t2), file("mid.md", t1)])
        XCTAssertEqual(node.sortedChildren(by: .modified).map(\.name), ["new.md", "mid.md", "old.md"])
    }

    func testSortByModifiedFoldersUseSubtreeDate() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 3000)
        // Папки без собственной mtime, но с разными датами вложенных файлов → сортируются по субдереву.
        let node = dir("R", [
            dir("R/Old", [file("R/Old/a.md", t0)]),
            dir("R/New", [file("R/New/b.md", t2)]),
        ])
        XCTAssertEqual(node.sortedChildren(by: .modified).map(\.name), ["New", "Old"])
    }

    // MARK: - URL.crumbSegments

    func testCrumbSegments() {
        XCTAssertEqual(root.appendingPathComponent("Reference/python-shpargalka.md").crumbSegments(from: root),
                       ["Reference", "python-shpargalka"])
        XCTAssertEqual(root.appendingPathComponent("note.md").crumbSegments(from: root), ["note"])
        // вне корня → лист без .md
        XCTAssertEqual(URL(fileURLWithPath: "/Other/x.md").crumbSegments(from: root), ["x"])
        // без корня
        XCTAssertEqual(root.appendingPathComponent("a/b.md").crumbSegments(from: nil), ["b"])
    }

    // MARK: - AppLanguage.filesCount (локализованное согласование)

    func testFilesCountPlural() {
        // RU — 3-форма
        XCTAssertEqual(AppLanguage.ru.filesCount(1), "1 файл")
        XCTAssertEqual(AppLanguage.ru.filesCount(2), "2 файла")
        XCTAssertEqual(AppLanguage.ru.filesCount(4), "4 файла")
        XCTAssertEqual(AppLanguage.ru.filesCount(5), "5 файлов")
        XCTAssertEqual(AppLanguage.ru.filesCount(9), "9 файлов")
        XCTAssertEqual(AppLanguage.ru.filesCount(11), "11 файлов")
        XCTAssertEqual(AppLanguage.ru.filesCount(21), "21 файл")
        XCTAssertEqual(AppLanguage.ru.filesCount(24), "24 файла")
        XCTAssertEqual(AppLanguage.ru.filesCount(0), "0 файлов")
        // EN / ZH
        XCTAssertEqual(AppLanguage.en.filesCount(1), "1 file")
        XCTAssertEqual(AppLanguage.en.filesCount(3), "3 files")
        XCTAssertEqual(AppLanguage.zh.filesCount(3), "3 个文件")
    }

    func testRelativeOrJustNow() {
        let now = Date()
        XCTAssertEqual(Formatting.relativeOrJustNow(now, now: now, justNow: "только что"), "только что")
        XCTAssertEqual(Formatting.relativeOrJustNow(now.addingTimeInterval(-5), now: now, justNow: "now"), "now")
        // > 60с — уже не «только что»
        XCTAssertNotEqual(Formatting.relativeOrJustNow(now.addingTimeInterval(-3600), now: now, justNow: "now"), "now")
    }

    func testShouldCheck() {
        let now = Date()
        XCTAssertTrue(Formatting.shouldCheck(last: nil, now: now, interval: 3600))
        XCTAssertFalse(Formatting.shouldCheck(last: now.addingTimeInterval(-60), now: now, interval: 3600))
        XCTAssertTrue(Formatting.shouldCheck(last: now.addingTimeInterval(-7200), now: now, interval: 3600))
    }

    func testAppVersionNonEmpty() {
        XCTAssertFalse(CoreKit.appVersion.isEmpty)
    }

    // MARK: - Голосовой ввод: таймер + склейка текста

    func testElapsedClock() {
        XCTAssertEqual(Formatting.elapsedClock(0), "0:00")
        XCTAssertEqual(Formatting.elapsedClock(6), "0:06")
        XCTAssertEqual(Formatting.elapsedClock(59), "0:59")
        XCTAssertEqual(Formatting.elapsedClock(60), "1:00")
        XCTAssertEqual(Formatting.elapsedClock(75), "1:15")
        XCTAssertEqual(Formatting.elapsedClock(605), "10:05")
        XCTAssertEqual(Formatting.elapsedClock(-3), "0:00")   // защита от отрицательного
    }

    func testGitTokenAccountPerVault() {
        let a = SecretStore.gitTokenAccount(for: "/Users/me/VaultA")
        let b = SecretStore.gitTokenAccount(for: "/Users/me/VaultB")
        XCTAssertNotEqual(a, b)                              // разные хранилища → разные ключи токена
        XCTAssertNotEqual(a, SecretStore.gitTokenAccount)    // не совпадает с legacy-общим
        XCTAssertTrue(a.contains("/Users/me/VaultA"))        // ключ привязан к пути
    }

    func testAppLanguageFromSystem() {
        XCTAssertEqual(AppLanguage.fromSystem(["ru-RU"]), .ru)
        XCTAssertEqual(AppLanguage.fromSystem(["zh-Hans-CN"]), .zh)
        XCTAssertEqual(AppLanguage.fromSystem(["zh-TW"]), .zh)
        XCTAssertEqual(AppLanguage.fromSystem(["en-US"]), .en)
        XCTAssertEqual(AppLanguage.fromSystem(["fr-FR", "de-DE"]), .en)   // неподдерживаемые → English
        XCTAssertEqual(AppLanguage.fromSystem([]), .en)                  // пусто → English (не русский)
        XCTAssertEqual(AppLanguage.fromSystem(["fr-FR", "ru-RU"]), .ru)  // первый поддерживаемый в списке
    }

    func testGitCommitMessage() {
        // Дата инъектируется → детерминированный числовой формат (локаль-независимо).
        var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 24; comps.hour = 17; comps.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let msg = Formatting.gitCommitMessage(action: "auto-sync", date: date)
        XCTAssertEqual(msg, "Sage · auto-sync · 2026-06-24 17:30")
        XCTAssertTrue(Formatting.gitCommitMessage(action: "автосинхронизация", date: date).contains("автосинхронизация"))
    }

    func testStringNormalizers() {
        // normalizedLinkTarget: percent-decode + снять <> и пробелы
        XCTAssertEqual("Helpers/A%20B.md".normalizedLinkTarget, "Helpers/A B.md")
        XCTAssertEqual("<Helpers/A B.md>".normalizedLinkTarget, "Helpers/A B.md")
        XCTAssertEqual("  note.md  ".normalizedLinkTarget, "note.md")
        XCTAssertEqual("plain.md".normalizedLinkTarget, "plain.md")
        // normalizedSearchKey: trim + lowercase
        XCTAssertEqual("  Hello World  ".normalizedSearchKey, "hello world")
        XCTAssertEqual("ЗАМЕТКА".normalizedSearchKey, "заметка")
    }

    func testVoiceShowsOrbOverlay() {
        XCTAssertFalse(voiceShowsOrbOverlay(.off))            // покой → инпут/хедер видны
        XCTAssertTrue(voiceShowsOrbOverlay(.permission))
        XCTAssertTrue(voiceShowsOrbOverlay(.listening))
        XCTAssertTrue(voiceShowsOrbOverlay(.transcribing))   // и в распознавании инпут/хедер скрыты (не мелькают)
    }

    func testMergeVoiceText() {
        XCTAssertEqual(Formatting.mergeVoiceText(prefix: "", transcript: "привет"), "привет")        // пустой префикс
        XCTAssertEqual(Formatting.mergeVoiceText(prefix: "заметка", transcript: "привет"), "заметка привет")  // склейка
        XCTAssertEqual(Formatting.mergeVoiceText(prefix: "заметка", transcript: "  привет  "), "заметка привет") // trim
        XCTAssertEqual(Formatting.mergeVoiceText(prefix: "x", transcript: "   "), "x")               // пустой transcript → префикс
        // partial→finished НЕ двоится: оба раза склеиваем от ОДНОГО префикса
        let prefix = "заметка"
        let afterPartial = Formatting.mergeVoiceText(prefix: prefix, transcript: "прив")
        let afterFinished = Formatting.mergeVoiceText(prefix: prefix, transcript: "привет")
        XCTAssertEqual(afterPartial, "заметка прив")
        XCTAssertEqual(afterFinished, "заметка привет")   // НЕ «заметка прив привет»
    }

    // MARK: - ChatContext.historyPath

    func testHistoryPath() {
        XCTAssertEqual(ChatContext.vault.historyPath(vaultRoot: root), "Всё хранилище")
        XCTAssertEqual(ChatContext.file(name: "python-shpargalka", path: "/V/Reference/python-shpargalka.md")
            .historyPath(vaultRoot: root), "Reference/python-shpargalka.md")
        XCTAssertEqual(ChatContext.folder(name: "Reference", fileCount: 9, path: "/V/Reference")
            .historyPath(vaultRoot: root), "Reference/")
        XCTAssertEqual(ChatContext.selection(fileName: "note.md").historyPath(vaultRoot: root), "note.md")
    }

    // MARK: - ChatHistory grouping

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testBucketing() {
        let now = date(2026, 6, 23, 10)
        XCTAssertEqual(ChatHistory.bucket(for: date(2026, 6, 23, 8), now: now), .today)
        XCTAssertEqual(ChatHistory.bucket(for: date(2026, 6, 22, 23), now: now), .yesterday)
        XCTAssertEqual(ChatHistory.bucket(for: date(2026, 6, 20), now: now), .earlier)
    }

    func testGroupOrdersBucketsAndDropsEmpty() {
        let now = date(2026, 6, 23, 10)
        func s(_ d: Date) -> ChatSession { ChatSession(title: "t", context: .vault, updatedAt: d) }
        let groups = ChatHistory.group([s(date(2026, 6, 20)), s(date(2026, 6, 23, 9)), s(date(2026, 6, 23, 8))], now: now)
        XCTAssertEqual(groups.map(\.bucket), [.today, .earlier])   // нет «вчера» → корзина опущена
        XCTAssertEqual(groups[0].sessions.count, 2)
        XCTAssertEqual(groups[1].sessions.count, 1)
    }
}
