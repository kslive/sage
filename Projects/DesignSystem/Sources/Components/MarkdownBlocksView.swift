import CoreKit
import SwiftUI

/// Рендер массива `MarkdownBlock` в нативные SwiftUI-вью (превью редактора и ответы чата).
public struct MarkdownBlocksView: View {
    private let blocks: [MarkdownBlock]
    private let onToggleCheck: ((Int) -> Void)?
    @Environment(\.palette) private var palette

    public init(_ blocks: [MarkdownBlock], onToggleCheck: ((Int) -> Void)? = nil) {
        self.blocks = blocks
        self.onToggleCheck = onToggleCheck
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                row(for: block, isFirst: idx == 0)
            }
        }
    }

    @ViewBuilder private func row(for block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .font(headingFont(level))
                .tracking(level <= 2 ? -0.4 : 0)
                .foregroundStyle(palette.tx)
                .padding(.top, isFirst ? 0 : (level <= 2 ? 14 : 8))
        case let .paragraph(text):
            Text(text).sageType(.ui).foregroundStyle(palette.tx).lineSpacing(4)
        case let .checkItem(checked, text, line):
            HStack(alignment: .center, spacing: 10) {
                checkbox(checked: checked, line: line)
                Text(text).sageType(.ui)
                    .foregroundStyle(checked ? palette.tx3 : palette.tx)
                    .strikethrough(checked, color: palette.tx3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .bullet(text, depth):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle().fill(palette.tx3).frame(width: 4, height: 4).padding(.top, 7)
                Text(text).sageType(.ui).foregroundStyle(palette.tx)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case let .numbered(index, text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(index).").sageType(.ui).foregroundStyle(palette.tx3).monospacedDigit()
                Text(text).sageType(.ui).foregroundStyle(palette.tx)
            }
        case let .quote(text):
            HStack(spacing: 0) {
                Rectangle().fill(palette.bd2).frame(width: 3)
                Text(text).sageType(.ui).foregroundStyle(palette.tx2).italic().padding(.leading, 12)
            }
        case let .callout(_, text):
            HStack(alignment: .top, spacing: 11) {
                SparkMark(size: 16, color: palette.ac)
                Text(text).sageType(.ui).foregroundStyle(palette.tx)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.acs, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.bd, lineWidth: 1))
        case let .code(language, code):
            VStack(alignment: .leading, spacing: 0) {
                if let language {
                    Text(language).font(.system(size: 10.5)).foregroundStyle(palette.tx3)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.bg2)
                }
                Text(code).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(palette.tx)
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bg1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd, lineWidth: 1))
        case let .table(headers, rows):
            tableView(headers: headers, rows: rows)
        case .divider:
            Rectangle().fill(palette.bd).frame(height: 1).padding(.vertical, 6)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: SageFontFamily.font(SageFontFamily.display, size: 30, systemWeight: .bold)
        case 2: SageFontFamily.font(SageFontFamily.display, size: 21, systemWeight: .bold)
        default: SageFontFamily.font(SageFontFamily.textSemibold, size: 17, systemWeight: .semibold)
        }
    }

    private func checkbox(checked: Bool, line: Int) -> some View {
        Button {
            onToggleCheck?(line)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(checked ? palette.ac : .clear)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(checked ? .clear : palette.bd2, lineWidth: 1.6)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(onToggleCheck == nil)
    }

    private func tableView(headers: [AttributedString], rows: [[AttributedString]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header).sageType(.uiMedium).foregroundStyle(palette.tx)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            .background(palette.bg2)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().overlay(palette.bd)
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell).sageType(.ui).foregroundStyle(palette.tx2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.bd, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
