import AppKit
import CoreKit
import Foundation
import Localization
import Observation
import SettingsStore
import UpdateService

/// Состояние и логика обновлений (вкладка «Обновления» + фоновые проверки на уровне приложения).
/// Авто-режим: скачать+проверить+подготовить в фоне → `.readyToInstall` (применяется при выходе/перезапуске).
@MainActor
@Observable
public final class UpdaterViewModel {
    public private(set) var phase: UpdaterPhase = .idle
    /// Релиз, который сейчас качаем/готов — для подписи «Загрузка X…» и кнопки «Перезапустить».
    public private(set) var pendingRelease: UpdateRelease?

    /// Анонс «Что нового» после обновления (нотсы ТЕКУЩЕЙ версии с GitHub) — показывается один раз.
    public struct WhatsNew: Equatable {
        public let version: String
        public let body: String
    }
    public private(set) var whatsNew: WhatsNew?

    private let updater: UpdateServicing
    private let settings: SettingsStore
    private let locale: LocaleManager
    private var task: Task<Void, Never>?
    private var stagedApp: URL?

    /// Троттл фоновых проверок (старт/фокус/таймер): не чаще раза в 6 ч. «Проверить сейчас» — без троттла.
    private let backgroundInterval: TimeInterval = 6 * 3600

    public init(updater: UpdateServicing, settings: SettingsStore, locale: LocaleManager) {
        self.updater = updater
        self.settings = settings
        self.locale = locale
        if let last = settings.lastUpdateCheck { phase = .upToDate(last) }
        if settings.pendingUpdateVersion == CoreKit.appVersion {
            settings.pendingUpdateVersion = nil
            settings.pendingUpdatePath = nil
        }
    }

    private var s: Strings { locale.strings }
    public var currentVersion: String { CoreKit.appVersion }
    public var lastCheck: Date? { settings.lastUpdateCheck }

    /// Загрузить анонс «Что нового» — один раз на версию. Пустые/отсутствующие нотсы помечаются
    /// без показа; сетевая ошибка НЕ помечает (окно покажется при следующем онлайн-запуске).
    public func maybeLoadWhatsNew() async {
        let current = CoreKit.appVersion
        guard settings.whatsNewShownVersion != current else { return }
        do {
            guard let body = try await updater.releaseNotes(repo: CoreKit.updatesRepo, version: current),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                settings.whatsNewShownVersion = current
                return
            }
            whatsNew = WhatsNew(version: current, body: body)
        } catch {}
    }

    public func dismissWhatsNew() {
        settings.whatsNewShownVersion = CoreKit.appVersion
        whatsNew = nil
    }

    /// Фоновая проверка (старт/фокус/таймер) — троттлится; качает в фоне только при autoUpdate.
    public func checkInBackground() {
        guard Formatting.shouldCheck(last: settings.lastUpdateCheck, interval: backgroundInterval) else { return }
        check(silent: true)
    }

    /// Явная проверка по кнопке «Проверить сейчас» (без троттла).
    public func checkNow() { check(silent: false) }

    private func check(silent: Bool) {
        switch phase {
        case .downloading, .installing: return
        default: break
        }
        task?.cancel()
        if !silent { phase = .checking }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await updater.checkForUpdate(repo: CoreKit.updatesRepo,
                                                               current: CoreKit.appVersion, channel: .stable)
                settings.lastUpdateCheck = Date()
                guard let release else { phase = .upToDate(Date()); return }
                if settings.pendingUpdateVersion == release.version,
                   let path = settings.pendingUpdatePath, FileManager.default.fileExists(atPath: path) {
                    pendingRelease = release
                    stagedApp = URL(fileURLWithPath: path)
                    phase = .readyToInstall(release)
                } else if silent, settings.autoUpdate {
                    downloadAndInstall(release)
                } else {
                    phase = .available(release)
                }
            } catch {
                if !silent { phase = .failed(message(error)) }
            }
        }
    }

    /// Кнопка «Обновить» из баннера доступной версии.
    public func update() {
        guard case let .available(release) = phase else { return }
        downloadAndInstall(release)
    }

    private func downloadAndInstall(_ release: UpdateRelease) {
        task?.cancel()
        pendingRelease = release
        phase = .downloading(0)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var zip: URL?
                for try await event in updater.downloadAndVerify(release) {
                    switch event {
                    case let .progress(p): phase = .downloading(p.fraction)
                    case let .finished(url): zip = url
                    }
                }
                guard let zip else { phase = .failed(s.settings.downloadIncomplete); return }
                phase = .installing
                let staged = try await updater.stage(zipURL: zip)
                stagedApp = staged
                settings.pendingUpdateVersion = release.version
                settings.pendingUpdatePath = staged.path
                phase = .readyToInstall(release)
            } catch {
                phase = .failed(message(error))
            }
        }
    }

    /// «Перезапустить» — применить подготовленное обновление после выхода и перезапустить на новую версию.
    public func restart() {
        guard prepareUpdateForRestart() else { return }
        NSApplication.shared.terminate(nil)
    }

    /// Подготовка к перезапуску (тестируемая часть `restart`, без `terminate`): снять pending (чтобы
    /// `applicationWillTerminate` не применил повторно) и взвести detached-хелпер замены с relaunch.
    /// Возвращает false, если применять нечего. Вызывать ТОЛЬКО из restart() / тестов.
    @discardableResult
    public func prepareUpdateForRestart() -> Bool {
        let path = stagedApp?.path ?? settings.pendingUpdatePath
        guard let path else { return false }
        settings.pendingUpdateVersion = nil
        settings.pendingUpdatePath = nil
        updater.applyOnQuit(stagedApp: URL(fileURLWithPath: path), relaunch: true)
        return true
    }

    /// Локализованное сообщение ошибки (типизированные кейсы апдейтера → строки UI).
    private func message(_ error: Error) -> String {
        if let e = error as? UpdateError {
            switch e {
            case .badResponse: return s.settings.updateErrNetwork
            case .checksumMismatch: return s.settings.updateErrChecksum
            case .noAppInArchive: return s.settings.updateErrNoApp
            case .installFailed: return s.settings.updateErrInstall
            }
        }
        return s.settings.updateErrNetwork
    }
}
