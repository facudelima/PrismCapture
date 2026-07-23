import AppKit
import SwiftUI
import Combine

@MainActor
final class AnnotationViewModel: ObservableObject {
    @Published var image: NSImage
    @Published var annotations: [Annotation] = []
    @Published var undoStack: [[Annotation]] = []
    @Published var redoStack: [[Annotation]] = []
    @Published var selectedTool: EditorTool = .select
    @Published var strokeColor: Color = .red
    @Published var strokeWidth: StrokeWidth = .regular
    @Published var draft: Annotation?
    @Published var nextMarkerNumber = 1
    @Published var ocrText: String = ""
    @Published var isOCRLoading = false
    @Published var showOCRPanel = false
    @Published var remoteURL: URL?
    @Published var deleteHash: String?
    @Published var isUploading = false
    @Published var editingTextID: UUID?
    @Published var editingTextDraft: String = ""
    /// Prevents the global Enter-to-copy shortcut from firing right after committing text.
    @Published private(set) var suppressReturnShortcut = false
    /// Live NSTextField while typing — Enter reads from here.
    weak var activeTextField: NSTextField?

    private var draggingID: UUID?
    private var dragStartPoint: CGPoint?
    private var dragOriginalPoints: [CGPoint]?
    private var dragDidPushUndo = false

    /// Coordinate space of the on-screen canvas (points). Annotations live in this space.
    var canvasSize: CGSize

    let originalImage: NSImage

    init(image: NSImage, canvasSize: CGSize? = nil) {
        self.image = image
        self.originalImage = image
        self.canvasSize = canvasSize ?? image.size
    }

    /// Replaces the underlying screenshot when the capture frame is moved (Lightshot-style).
    func replaceCapture(with newImage: NSImage) {
        image = newImage
        // Pixel-baked effects no longer match the new pixels.
        annotations.removeAll { $0.tool == .blur || $0.tool == .pixelate }
        draft = nil
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var isEditingText: Bool { editingTextID != nil }
    var isDraggingAnnotation: Bool { draggingID != nil }

    func currentEditingString() -> String {
        if let field = activeTextField {
            if let editor = field.currentEditor() {
                return editor.string
            }
            return field.stringValue
        }
        return editingTextDraft
    }

    func editingTextOrigin() -> CGPoint? {
        guard let editingTextID,
              let annotation = annotations.first(where: { $0.id == editingTextID }),
              let point = annotation.points.first
        else { return nil }
        return point
    }

    func commitTextEdit(with rawText: String? = nil) {
        guard let editingTextID,
              let index = annotations.firstIndex(where: { $0.id == editingTextID })
        else {
            cancelTextEdit()
            return
        }
        let source = rawText ?? currentEditingString()
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTextDraft = trimmed
        if trimmed.isEmpty {
            annotations.remove(at: index)
        } else {
            annotations[index].text = trimmed
        }
        self.editingTextID = nil
        activeTextField = nil
        suppressReturnShortcut = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.suppressReturnShortcut = false
        }
    }

    func cancelTextEdit() {
        if let editingTextID,
           let index = annotations.firstIndex(where: { $0.id == editingTextID }) {
            annotations.remove(at: index)
        }
        editingTextID = nil
        editingTextDraft = ""
        activeTextField = nil
        suppressReturnShortcut = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.suppressReturnShortcut = false
        }
    }

    /// Crops the base image to a canvas-space rect and applies blur or pixelate.
    func processedRegionImage(tool: EditorTool, canvasRect: CGRect) -> CGImage? {
        guard canvasRect.width > 2, canvasRect.height > 2,
              let cgImage = image.cgImage
        else { return nil }

        let sx = CGFloat(cgImage.width) / max(canvasSize.width, 1)
        let sy = CGFloat(cgImage.height) / max(canvasSize.height, 1)
        var pixelRect = CGRect(
            x: canvasRect.minX * sx,
            y: canvasRect.minY * sy,
            width: canvasRect.width * sx,
            height: canvasRect.height * sy
        ).integral
        pixelRect = pixelRect.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard pixelRect.width > 1, pixelRect.height > 1,
              let cropped = cgImage.cropping(to: pixelRect)
        else { return nil }

        switch tool {
        case .blur:
            return cropped.blurred(radius: max(10, min(pixelRect.width, pixelRect.height) * 0.08))
        case .pixelate:
            let block = max(6, Int(min(pixelRect.width, pixelRect.height) / 16))
            return cropped.pixelated(blockSize: block)
        default:
            return nil
        }
    }

    func hitTestText(at point: CGPoint) -> UUID? {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium)
        ]
        for annotation in annotations.reversed() where annotation.tool == .text && !annotation.text.isEmpty {
            guard let origin = annotation.points.first else { continue }
            let size = (annotation.text as NSString).size(withAttributes: attrs)
            let rect = CGRect(
                x: origin.x - 6,
                y: origin.y - 4,
                width: max(size.width + 12, 48),
                height: max(size.height + 8, 28)
            )
            if rect.contains(point) {
                return annotation.id
            }
        }
        return nil
    }

    func beginDraggingText(id: UUID, at point: CGPoint) {
        guard let annotation = annotations.first(where: { $0.id == id }) else { return }
        draggingID = id
        dragStartPoint = point
        dragOriginalPoints = annotation.points
        dragDidPushUndo = false
    }

    func continueDragging(to point: CGPoint) {
        guard let id = draggingID,
              let start = dragStartPoint,
              let original = dragOriginalPoints,
              let index = annotations.firstIndex(where: { $0.id == id })
        else { return }

        if !dragDidPushUndo {
            pushUndo()
            dragDidPushUndo = true
        }

        let dx = point.x - start.x
        let dy = point.y - start.y
        annotations[index].points = original.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    func endDragging() {
        draggingID = nil
        dragStartPoint = nil
        dragOriginalPoints = nil
        dragDidPushUndo = false
    }

    func pushUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func beginStroke(at point: CGPoint) {
        switch selectedTool {
        case .select:
            return
        case .text:
            pushUndo()
            let annotation = Annotation(tool: .text, color: strokeColor, points: [point], text: "")
            annotations.append(annotation)
            editingTextID = annotation.id
            editingTextDraft = ""
        case .emoji:
            return
        case .marker:
            pushUndo()
            annotations.append(Annotation(tool: .marker, color: strokeColor, points: [point], markerNumber: nextMarkerNumber))
            nextMarkerNumber += 1
        default:
            draft = Annotation(
                tool: selectedTool,
                color: strokeColor.opacity(selectedTool == .highlighter ? 0.35 : 1),
                lineWidth: selectedTool == .highlighter ? strokeWidth.rawValue * 2.2 : strokeWidth.rawValue,
                points: [point],
                rect: CGRect(origin: point, size: .zero)
            )
        }
    }

    func continueStroke(to point: CGPoint) {
        guard var draft else { return }
        switch selectedTool {
        case .pencil, .highlighter:
            draft.points.append(point)
        default:
            guard let start = draft.points.first else { return }
            draft.points = [start, point]
            draft.rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
        }
        self.draft = draft
    }

    func endStroke() {
        guard let draft else { return }
        pushUndo()
        annotations.append(draft)
        self.draft = nil
    }

    func renderedImage() -> NSImage {
        let annotationsSnapshot = annotations
        let sx = image.size.width / max(canvasSize.width, 1)
        let sy = image.size.height / max(canvasSize.height, 1)
        return image.flattened { context, size in
            let mirror = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
            context.concatenate(mirror)
            context.scaleBy(x: sx, y: sy)
            for annotation in annotationsSnapshot {
                Self.draw(annotation, in: context, effectImage: processedRegionImage(tool: annotation.tool, canvasRect: annotation.rect))
            }
        }
    }

    private func scaleRectToImage(_ rect: CGRect) -> CGRect {
        let sx = image.size.width / max(canvasSize.width, 1)
        let sy = image.size.height / max(canvasSize.height, 1)
        return CGRect(
            x: rect.origin.x * sx,
            y: rect.origin.y * sy,
            width: rect.width * sx,
            height: rect.height * sy
        )
    }

    static func draw(_ annotation: Annotation, in context: CGContext, effectImage: CGImage? = nil) {
        let color = NSColor(annotation.color)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.tool {
        case .rectangle:
            context.stroke(annotation.rect)
        case .circle:
            context.strokeEllipse(in: annotation.rect)
        case .line:
            guard annotation.points.count >= 2 else { return }
            context.move(to: annotation.points[0])
            context.addLine(to: annotation.points[1])
            context.strokePath()
        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: annotation.points[0], to: annotation.points[1], in: context, width: annotation.lineWidth)
        case .pencil, .highlighter:
            guard let first = annotation.points.first else { return }
            context.move(to: first)
            for point in annotation.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        case .blur, .pixelate:
            if let effectImage {
                context.interpolationQuality = annotation.tool == .pixelate ? .none : .high
                context.draw(effectImage, in: annotation.rect)
            } else {
                context.setFillColor(NSColor.black.withAlphaComponent(0.22).cgColor)
                context.fill(annotation.rect)
            }
        case .text:
            guard let point = annotation.points.first, !annotation.text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: color
            ]
            NSAttributedString(string: annotation.text, attributes: attrs)
                .draw(at: point)
        case .marker:
            guard let point = annotation.points.first else { return }
            let radius: CGFloat = 14
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: rect)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let text = "\(annotation.markerNumber)" as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attrs)
        case .emoji:
            guard let point = annotation.points.first else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 28)
            ]
            (annotation.emoji as NSString).draw(at: point, withAttributes: attrs)
        case .select:
            break
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext, width: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(16, width * 4.0)
        let headWidth = max(12, width * 3.2)
        let clampedHead = min(headLength, length * 0.45)

        let shaftEnd = CGPoint(
            x: end.x - clampedHead * cos(angle),
            y: end.y - clampedHead * sin(angle)
        )

        context.setLineWidth(width)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let perpX = -sin(angle)
        let perpY = cos(angle)
        let left = CGPoint(
            x: shaftEnd.x + (headWidth / 2) * perpX,
            y: shaftEnd.y + (headWidth / 2) * perpY
        )
        let right = CGPoint(
            x: shaftEnd.x - (headWidth / 2) * perpX,
            y: shaftEnd.y - (headWidth / 2) * perpY
        )

        context.move(to: end)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()
    }

    func runOCR() async {
        isOCRLoading = true
        defer { isOCRLoading = false }
        do {
            ocrText = try await OCRService.shared.extractText(from: renderedImage())
            showOCRPanel = true
        } catch {
            ocrText = error.localizedDescription
            showOCRPanel = true
        }
    }

    func upload() async {
        let provider = AppSettings.shared.uploadProvider
        isUploading = true
        defer { isUploading = false }
        do {
            let result = try await UploadService.shared.upload(renderedImage(), provider: provider)
            remoteURL = result.url
            deleteHash = result.deleteHash
            ClipboardService.shared.copyURL(result.url)
        } catch {
            remoteURL = nil
        }
    }

    func deleteRemote() async {
        guard let remoteURL else { return }
        do {
            try await UploadService.shared.delete(
                remoteURL: remoteURL.absoluteString,
                deleteHash: deleteHash,
                provider: AppSettings.shared.uploadProvider
            )
            self.remoteURL = nil
            self.deleteHash = nil
        } catch {
            // Keep URL; user can retry.
        }
    }
}
