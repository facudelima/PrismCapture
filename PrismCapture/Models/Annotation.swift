import Foundation
import SwiftUI

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var tool: EditorTool
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]
    var text: String
    var emoji: String
    var markerNumber: Int
    var rect: CGRect

    init(
        id: UUID = UUID(),
        tool: EditorTool,
        color: Color = .red,
        lineWidth: CGFloat = 4,
        points: [CGPoint] = [],
        text: String = "",
        emoji: String = "😀",
        markerNumber: Int = 1,
        rect: CGRect = .zero
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.lineWidth = lineWidth
        self.points = points
        self.text = text
        self.emoji = emoji
        self.markerNumber = markerNumber
        self.rect = rect
    }

    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
            && lhs.tool == rhs.tool
            && lhs.points == rhs.points
            && lhs.text == rhs.text
            && lhs.emoji == rhs.emoji
            && lhs.markerNumber == rhs.markerNumber
            && lhs.rect == rhs.rect
            && lhs.lineWidth == rhs.lineWidth
    }
}
