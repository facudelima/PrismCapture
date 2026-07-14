import SwiftUI
import AppKit

/// Lightshot-style editor: screenshot pinned where it was captured, toolbar floating under it.
/// Drag with the Select/Mover tool to pan the frame — the image re-captures what's underneath.
struct InPlaceEditorView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    @ObservedObject var captureVM: CaptureViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var livePin: CGRect
    @State private var isMovingPin = false
    @State private var recaptureTask: Task<Void, Never>?
    @State private var recaptureToken = 0

    init(annotationVM: AnnotationViewModel, captureVM: CaptureViewModel, pinRect: CGRect) {
        self.annotationVM = annotationVM
        self.captureVM = captureVM
        _livePin = State(initialValue: pinRect)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DimmedBackgroundView(selection: livePin, windowHighlight: nil)
                .allowsHitTesting(true)
                .contentShape(Rectangle())
                .onTapGesture {
                    OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
                }

            // While moving: hide the frozen bitmap so the hole shows the live desktop
            // underneath (Lightshot pan). Recapture only when the drag ends.
            ZStack {
                StableAnnotationCanvas(
                    viewModel: annotationVM,
                    canvasSize: livePin.size,
                    onMovePin: movePin(by:)
                )
                .opacity(isMovingPin ? 0 : 1)

                if isMovingPin {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(.white.opacity(0.95), lineWidth: 1.5)
                        .background {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 3)
                                .blur(radius: 0.4)
                        }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: livePin.width, height: livePin.height)
            .position(x: livePin.midX, y: livePin.midY)
            .shadow(color: .black.opacity(isMovingPin ? 0 : 0.35), radius: 16, y: 6)

            EditorToolbarView(viewModel: annotationVM, captureVM: captureVM, compact: true)
                .position(toolbarPosition)
                .transition(.scale.combined(with: .opacity))

            if annotationVM.showOCRPanel {
                OCRResultPanel(text: $annotationVM.ocrText, isPresented: $annotationVM.showOCRPanel)
                    .position(
                        x: min(livePin.maxX + 170, OverlayWindowController.shared.overlayFrame.width - 180),
                        y: livePin.midY
                    )
            }

            if let toast = captureVM.toastMessage {
                ToastView(message: toast)
                    .position(x: OverlayWindowController.shared.overlayFrame.width / 2, y: 56)
            }
        }
        .frame(
            width: OverlayWindowController.shared.overlayFrame.width,
            height: OverlayWindowController.shared.overlayFrame.height
        )
        .preferredColorScheme(settings.theme.colorScheme)
        .focusable()
        .onKeyPress(keys: [.init("c")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            copyAndClose()
            return .handled
        }
        .onKeyPress(keys: [.init("s")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            save()
            return .handled
        }
        .onKeyPress(keys: [.init("z")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) {
                annotationVM.redo()
            } else {
                annotationVM.undo()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if annotationVM.isEditingText {
                annotationVM.cancelTextEdit()
                return .handled
            }
            OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
            return .handled
        }
        .onKeyPress(.return) {
            if annotationVM.isEditingText {
                annotationVM.commitTextEdit(with: annotationVM.currentEditingString())
                return .handled
            }
            if annotationVM.suppressReturnShortcut {
                return .handled
            }
            return .ignored
        }
    }

    private func movePin(by delta: CGSize) {
        if delta == .zero {
            // Drag ended → snap a fresh capture of what's inside the frame.
            scheduleRecapture()
            return
        }
        if !isMovingPin {
            isMovingPin = true
            // Cancel any in-flight preview capture from a previous move.
            recaptureTask?.cancel()
            recaptureToken += 1
        }
        var next = livePin.offsetBy(dx: delta.width, dy: delta.height)
        let overlay = OverlayWindowController.shared.overlayFrame
        next.origin.x = min(max(0, next.origin.x), max(0, overlay.width - next.width))
        next.origin.y = min(max(0, next.origin.y), max(0, overlay.height - next.height))
        livePin = next
    }

    private func scheduleRecapture() {
        recaptureTask?.cancel()
        recaptureToken += 1
        let token = recaptureToken
        let pin = livePin
        recaptureTask = Task { @MainActor in
            guard !Task.isCancelled, token == recaptureToken else { return }
            await recapture(at: pin, token: token)
            if token == recaptureToken {
                isMovingPin = false
            }
        }
    }

    private func recapture(at pin: CGRect, token: Int) async {
        let cocoaRect = OverlayWindowController.shared.globalCocoaRect(fromSwiftUI: pin)
        do {
            let image = try await CaptureService.shared.captureRectInGlobalCocoa(cocoaRect)
            guard token == recaptureToken else { return }
            annotationVM.replaceCapture(with: image)
        } catch {
            // Keep last good frame if capture fails.
        }
    }

    private func copyAndClose() {
        ClipboardService.shared.copyImage(annotationVM.renderedImage())
        if settings.showToastOnCopy {
            captureVM.showToast("Copiado al portapapeles")
        }
        OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
    }

    private var toolbarPosition: CGPoint {
        let overlay = OverlayWindowController.shared.overlayFrame
        let toolbarHeight: CGFloat = 52
        let gap: CGFloat = 14
        var y = livePin.maxY + gap + toolbarHeight / 2
        if y + toolbarHeight / 2 > overlay.height - 12 {
            y = livePin.minY - gap - toolbarHeight / 2
        }
        if y < toolbarHeight / 2 + 12 {
            y = min(livePin.midY, overlay.height - toolbarHeight / 2 - 12)
        }
        let x = min(max(livePin.midX, 200), overlay.width - 200)
        return CGPoint(x: x, y: y)
    }

    private func save() {
        if let url = FileService.shared.savePanel(image: annotationVM.renderedImage(), format: settings.imageFormat) {
            HistoryViewModel.shared.add(
                image: annotationVM.renderedImage(),
                fileURL: url,
                remoteURL: annotationVM.remoteURL,
                ocrText: annotationVM.ocrText.isEmpty ? nil : annotationVM.ocrText
            )
            if settings.clipboardBehavior == .copyOnSave {
                ClipboardService.shared.copyImage(annotationVM.renderedImage())
            }
            captureVM.showToast("Guardado")
        }
    }
}

/// Fixed-size canvas: image + annotations in the same coordinate space as the mouse.
struct StableAnnotationCanvas: View {
    @ObservedObject var viewModel: AnnotationViewModel
    let canvasSize: CGSize
    var onMovePin: ((CGSize) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: viewModel.image)
                .resizable()
                .interpolation(.high)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()

            AnnotationDrawingView(viewModel: viewModel)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(false)

            if viewModel.isEditingText, let origin = viewModel.editingTextOrigin() {
                InlineTextField(
                    viewModel: viewModel,
                    color: NSColor(viewModel.strokeColor),
                    onCommit: { viewModel.commitTextEdit(with: $0) },
                    onCancel: { viewModel.cancelTextEdit() }
                )
                .frame(minWidth: 140, idealWidth: 220, maxWidth: max(180, canvasSize.width - origin.x - 8), minHeight: 30)
                .offset(x: origin.x, y: origin.y)
                .zIndex(10)
                .id(viewModel.editingTextID)
            }

            AnnotationMouseRepresentable(viewModel: viewModel, onMovePin: onMovePin)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(true)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
        }
    }
}

struct AnnotationDrawingView: View {
    @ObservedObject var viewModel: AnnotationViewModel

    var body: some View {
        Canvas { context, _ in
            for annotation in viewModel.annotations {
                draw(annotation, in: &context, isDraft: false)
            }
            if let draft = viewModel.draft {
                draw(draft, in: &context, isDraft: true)
            }
            if let crop = viewModel.cropRect {
                context.stroke(Path(roundedRect: crop, cornerRadius: 2), with: .color(.white), lineWidth: 1.5)
            }
        }
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, isDraft: Bool) {
        let color = annotation.color
        switch annotation.tool {
        case .rectangle:
            context.stroke(Path(roundedRect: annotation.rect, cornerRadius: 2), with: .color(color), lineWidth: annotation.lineWidth)
        case .circle:
            context.stroke(Path(ellipseIn: annotation.rect), with: .color(color), lineWidth: annotation.lineWidth)
        case .line:
            guard annotation.points.count >= 2 else { return }
            var path = Path()
            path.move(to: annotation.points[0])
            path.addLine(to: annotation.points[1])
            context.stroke(path, with: .color(color), lineWidth: annotation.lineWidth)
        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: annotation.points[0], to: annotation.points[1], color: color, width: annotation.lineWidth, in: &context)
        case .pencil, .highlighter:
            guard let first = annotation.points.first else { return }
            var path = Path()
            path.move(to: first)
            for p in annotation.points.dropFirst() { path.addLine(to: p) }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)
            )
        case .blur, .pixelate:
            if !isDraft,
               let cgImage = viewModel.processedRegionImage(tool: annotation.tool, canvasRect: annotation.rect) {
                context.draw(
                    Image(decorative: cgImage, scale: 1),
                    in: annotation.rect
                )
            } else {
                // Preview while dragging the region.
                let fill = annotation.tool == .blur
                    ? Color.black.opacity(0.2)
                    : Color.black.opacity(0.15)
                context.fill(Path(annotation.rect), with: .color(fill))
                context.stroke(
                    Path(annotation.rect),
                    with: .color(color.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
        case .text:
            if annotation.text.isEmpty { return }
            if let p = annotation.points.first {
                context.draw(
                    Text(annotation.text).font(.system(size: 18, weight: .medium)).foregroundStyle(color),
                    at: p,
                    anchor: .topLeading
                )
            }
        case .marker:
            if let p = annotation.points.first {
                let r: CGFloat = 14
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
                context.draw(
                    Text("\(annotation.markerNumber)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white),
                    at: p,
                    anchor: .center
                )
            }
        case .emoji:
            if let p = annotation.points.first {
                context.draw(Text(annotation.emoji).font(.system(size: 28)), at: p, anchor: .topLeading)
            }
        case .select, .crop:
            break
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: Color, width: CGFloat, in context: inout GraphicsContext) {
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

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)
        context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))

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

        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

final class AnnotationMouseView: NSView {
    var viewModel: AnnotationViewModel?
    var onMovePin: ((CGSize) -> Void)?
    private var isMovingPin = false
    private var lastWindowPoint: CGPoint = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let viewModel else { return }

        if viewModel.isEditingText {
            viewModel.commitTextEdit(with: viewModel.editingTextDraft)
            return
        }

        // Drag existing text (any tool).
        if let textID = viewModel.hitTestText(at: point) {
            viewModel.beginDraggingText(id: textID, at: point)
            NSCursor.openHand.push()
            return
        }

        // Select tool (default): drag moves the whole capture on screen.
        if viewModel.selectedTool == .select {
            isMovingPin = true
            lastWindowPoint = event.locationInWindow
            NSCursor.closedHand.set()
            return
        }

        viewModel.beginStroke(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewModel, !viewModel.isEditingText else { return }
        let point = convert(event.locationInWindow, from: nil)

        if isMovingPin {
            let windowPoint = event.locationInWindow
            let dx = windowPoint.x - lastWindowPoint.x
            // Window coords are bottom-left; overlay SwiftUI is top-left.
            let dy = -(windowPoint.y - lastWindowPoint.y)
            lastWindowPoint = windowPoint
            onMovePin?(CGSize(width: dx, height: dy))
            return
        }

        if viewModel.isDraggingAnnotation {
            viewModel.continueDragging(to: point)
            return
        }

        if viewModel.selectedTool == .text || viewModel.selectedTool == .marker { return }
        viewModel.continueStroke(to: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewModel, !viewModel.isEditingText else { return }
        let point = convert(event.locationInWindow, from: nil)

        if isMovingPin {
            isMovingPin = false
            onMovePin?(.zero)
            NSCursor.openHand.set()
            return
        }

        if viewModel.isDraggingAnnotation {
            viewModel.continueDragging(to: point)
            viewModel.endDragging()
            NSCursor.pop()
            return
        }

        if viewModel.selectedTool == .text || viewModel.selectedTool == .marker { return }
        viewModel.continueStroke(to: point)
        viewModel.endStroke()
    }

    override func resetCursorRects() {
        guard let viewModel else { return }
        if viewModel.selectedTool == .select {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

struct AnnotationMouseRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: AnnotationViewModel
    var onMovePin: ((CGSize) -> Void)?

    func makeNSView(context: Context) -> AnnotationMouseView {
        let view = AnnotationMouseView()
        view.viewModel = viewModel
        view.onMovePin = onMovePin
        return view
    }

    func updateNSView(_ nsView: AnnotationMouseView, context: Context) {
        nsView.viewModel = viewModel
        nsView.onMovePin = onMovePin
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

/// Focusable text field for in-place annotation typing.
struct InlineTextField: NSViewRepresentable {
    @ObservedObject var viewModel: AnnotationViewModel
    var color: NSColor
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = "Escribí y Enter…"
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        field.textColor = .white
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.focusRingType = .none
        field.delegate = context.coordinator
        context.coordinator.installMonitor(for: field)
        context.coordinator.field = field
        viewModel.activeTextField = field
        viewModel.editingTextDraft = ""

        DispatchQueue.main.async {
            field.window?.makeKeyAndOrderFront(nil)
            _ = field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.field = nsView
        viewModel.activeTextField = nsView
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTextField
        weak var field: NSTextField?
        private var didFinish = false
        private var monitor: Any?

        init(_ parent: InlineTextField) {
            self.parent = parent
        }

        func installMonitor(for field: NSTextField) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let field = self.field else { return event }
                // Only handle keys while this field (or its field editor) is first responder.
                guard self.isFieldEditing(field) else { return event }

                switch event.keyCode {
                case 36, 76: // Return / keypad Enter
                    let text = self.liveString(from: field)
                    DispatchQueue.main.async {
                        self.finish(commit: true, text: text)
                    }
                    return nil
                case 53: // Escape
                    DispatchQueue.main.async {
                        self.finish(commit: false, text: "")
                    }
                    return nil
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            // Coordinator may deinit off main; monitor removal is best-effort.
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func isFieldEditing(_ field: NSTextField) -> Bool {
            guard let window = field.window else { return false }
            let first = window.firstResponder
            if first === field { return true }
            if let text = first as? NSText, text.delegate as AnyObject? === field { return true }
            if let view = first as? NSView, view.isDescendant(of: field) { return true }
            return field.currentEditor() != nil
        }

        private func liveString(from field: NSTextField) -> String {
            if let editor = field.currentEditor() {
                return editor.string
            }
            return field.stringValue
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.viewModel.editingTextDraft = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertLineBreak(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                finish(commit: true, text: textView.string)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                finish(commit: false, text: "")
                return true
            }
            return false
        }

        func finish(commit: Bool, text: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didFinish else { return }
                self.didFinish = true
                self.removeMonitor()
                self.parent.viewModel.editingTextDraft = text
                if commit {
                    self.parent.onCommit(text)
                } else {
                    self.parent.onCancel()
                }
            }
        }
    }
}
