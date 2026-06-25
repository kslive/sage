import SwiftUI

/// Линейные иконки редизайна (точные SVG-пути из макета Sage-Redesign).
/// Дуги транскрибированы с ПРОБЕЛАМИ между флагами (см. SVGPath).
public enum SageGlyph: Sendable {
    case chevron
    case folderClosed
    case folderOpen
    case fileDoc
    case copy
    case clock
    case clockLarge
    case trash
    case sort
    case viewList
    case plus
    case check
    case panel

    var path: String {
        switch self {
        case .chevron: "M6 4l4 4-4 4"
        case .folderClosed:
            "M2.5 6a1.5 1.5 0 0 1 1.5 -1.5h2.6c.43 0 .84 .18 1.13 .5l.74 .8a1.5 1.5 0 0 0 1.1 .48H16"
                + "A1.5 1.5 0 0 1 17.5 7.8V14A1.5 1.5 0 0 1 16 15.5H4A1.5 1.5 0 0 1 2.5 14V6z"
        case .folderOpen:
            "M2.5 6.2 3.6 5h3c.43 0 .84 .18 1.13 .5l.74 .8a1.5 1.5 0 0 0 1.1 .48H16"
                + "A1.5 1.5 0 0 1 17.5 8.3l-.7 5.9A1.5 1.5 0 0 1 15.3 15.5H4.2a1.5 1.5 0 0 1 -1.49 -1.32L2.5 6.2z"
        case .fileDoc:
            "M5 2.75h5.1L15.25 7.9V16A1.25 1.25 0 0 1 14 17.25H5A1.25 1.25 0 0 1 3.75 16V4"
                + "A1.25 1.25 0 0 1 5 2.75z M9.9 3v4.4h4.4"
        case .copy:
            "M7.1 5.5h4.8a1.6 1.6 0 0 1 1.6 1.6v4.8a1.6 1.6 0 0 1 -1.6 1.6H7.1a1.6 1.6 0 0 1 -1.6 -1.6V7.1"
                + "a1.6 1.6 0 0 1 1.6 -1.6z M3.5 10.5H3A1.5 1.5 0 0 1 1.5 9V3A1.5 1.5 0 0 1 3 1.5h6A1.5 1.5 0 0 1 10.5 3v.5"
        case .clock: "M2 8a6 6 0 1 0 12 0a6 6 0 1 0 -12 0M8 5v3l2 1.5"
        case .clockLarge: "M4.5 12.5a7.5 7.5 0 1 0 15 0a7.5 7.5 0 1 0 -15 0M12 9v3.5l2.3 1.6"
        case .trash: "M3.5 5h9M6.5 5V3.5h3V5M5 5l.5 8h5l.5-8"
        case .sort: "M4 2.5v11M4 13.5L2 11.5M4 13.5l2-2M11 13.5v-11M11 2.5L9 4.5M11 2.5l2 2"
        case .viewList: "M3 4.5h10M3 8h10M3 11.5h10"
        case .plus: "M8 3.5v9M3.5 8h9"
        case .check: "M3 8.5l3.2 3L13 4.5"
        case .panel:
            "M4 2.5h11a2.5 2.5 0 0 1 2.5 2.5v8a2.5 2.5 0 0 1 -2.5 2.5H4a2.5 2.5 0 0 1 -2.5 -2.5V5"
                + "a2.5 2.5 0 0 1 2.5 -2.5z M6.5 2.5V15.5"
        }
    }

    var viewBox: CGFloat {
        switch self {
        case .folderClosed, .folderOpen, .fileDoc: 20
        case .clockLarge: 24
        case .panel: 18
        default: 16
        }
    }

    var weight: CGFloat {
        switch self {
        case .chevron: 1.6
        case .folderClosed, .folderOpen: 1.4
        case .fileDoc: 1.35
        case .copy, .trash, .sort: 1.3
        case .clock, .viewList, .panel: 1.4
        case .clockLarge: 1.6
        case .plus: 1.5
        case .check: 1.7
        }
    }
}

/// Линейная иконка из `SageGlyph` (обводка с круглыми концами, масштаб по токену размера).
public struct SageGlyphIcon: View {
    let glyph: SageGlyph
    let size: CGFloat
    let color: Color

    public init(_ glyph: SageGlyph, size: CGFloat = 16, color: Color) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    public var body: some View {
        SVGShape(glyph.path, viewBox: CGSize(width: glyph.viewBox, height: glyph.viewBox))
            .stroke(color, style: StrokeStyle(
                lineWidth: glyph.weight * size / glyph.viewBox, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
