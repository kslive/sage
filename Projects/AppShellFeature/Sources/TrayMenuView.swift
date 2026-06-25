import CoreKit
import DesignSystem
import Localization
import SwiftUI

/// Содержимое трей-дропдауна (MenuBarExtra) — статус модели и быстрые действия.
public struct TrayMenuView: View {
    private let activeModelName: String
    private let ready: Bool
    private let onNewChat: () -> Void
    private let onSearch: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    @Environment(\.palette) private var palette
    @Environment(LocaleManager.self) private var locale

    public init(
        activeModelName: String, ready: Bool = true,
        onNewChat: @escaping () -> Void,
        onSearch: @escaping () -> Void, onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.activeModelName = activeModelName
        self.ready = ready
        self.onNewChat = onNewChat
        self.onSearch = onSearch
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    private var s: Strings { locale.strings }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                SparkLogo(size: 18, color: palette.ac)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sage").font(.sage(13, .semibold)).foregroundStyle(palette.tx)
                    HStack(spacing: 5) {
                        StatusDot(size: 6)
                        Text("\(activeModelName) · \(s.tray.statusRunning)")
                            .font(.sage(11.5)).foregroundStyle(palette.tx2)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)

            Divider().overlay(palette.bd).padding(.vertical, 4)

            if ready {
                row(icon: "bubble.left", title: s.tray.newChat, action: onNewChat)
                row(icon: "magnifyingglass", title: s.tray.search, action: onSearch)
                row(icon: "gearshape", title: s.tray.settings, action: onSettings)
                Divider().overlay(palette.bd).padding(.vertical, 4)
            }
            row(icon: "power", title: s.tray.quit, action: onQuit)
        }
        .padding(7)
        .frame(width: 280)
        .background(palette.bg2)
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(palette.tx2).frame(width: 18)
                Text(title).sageType(.ui).foregroundStyle(palette.tx)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(palette.bgh)
    }
}
