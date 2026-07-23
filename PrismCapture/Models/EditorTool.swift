import Foundation
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case circle
    case arrow
    case line
    case pencil
    case highlighter
    case blur
    case pixelate
    case text
    case marker
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Mover"
        case .rectangle: return "Rectángulo"
        case .circle: return "Círculo"
        case .arrow: return "Flecha"
        case .line: return "Línea"
        case .pencil: return "Lápiz"
        case .highlighter: return "Resaltador"
        case .blur: return "Desenfocar"
        case .pixelate: return "Pixelar / censurar"
        case .text: return "Texto"
        case .marker: return "Marcador"
        case .emoji: return "Emoji"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .text: return "textformat"
        case .marker: return "1.circle"
        case .emoji: return "face.smiling"
        }
    }

    var isDrawable: Bool {
        switch self {
        case .select, .text, .emoji:
            return false
        default:
            return true
        }
    }
}

enum StrokeWidth: CGFloat, CaseIterable, Identifiable {
    case thin = 2
    case regular = 4
    case bold = 7
    case heavy = 12

    var id: CGFloat { rawValue }
}
