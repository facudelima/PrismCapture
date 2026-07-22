import AppKit
import SwiftUI

/// Borderless overlay that can become key and always receives mouse hits,
/// even when visually transparent.
final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func awakeFromNib() {
        super.awakeFromNib()
        commonInit()
    }

    func commonInit() {
        isOpaque = false
        // Fully clear windows are skipped by AppKit hit-testing.
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        styleMask = [.borderless, .fullSizeContentView]
        appearance = AppSettings.shared.theme.resolvedWindowAppearance()
    }
}

/// Forwards mouse events reliably into the capture view model.
final class SelectionMouseView: NSView {
    var viewModel: CaptureViewModel?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true } // match SwiftUI top-left coordinates

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTracking()
    }

    override func layout() {
        super.layout()
        updateTracking()
        viewModel?.overlaySize = bounds.size
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Let SwiftUI receive clicks on the floating capture toolbar.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let viewModel, viewModel.isPointInToolbar(point) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let point = convert(event.locationInWindow, from: nil)
        guard let viewModel else { return }
        viewModel.overlaySize = bounds.size

        if viewModel.isWindowMode {
            viewModel.hoverWindows(at: point)
            return
        }
        // Always start a new selection drag (capture happens on mouse up).
        viewModel.dragKind = .creating
        viewModel.selectionStart = point
        viewModel.selectionRect = CGRect(origin: point, size: .zero)
        NSCursor.crosshair.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let viewModel else { return }

        if viewModel.isWindowMode {
            viewModel.hoverWindows(at: point)
            return
        }
        viewModel.handleSelectionMouseDragged(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let viewModel else { return }

        if viewModel.isWindowMode {
            viewModel.hoverWindows(at: point)
            viewModel.confirmSelection()
            return
        }

        viewModel.handleSelectionMouseDragged(at: point)
        viewModel.dragKind = .none
        if viewModel.selectionRect.width > 4, viewModel.selectionRect.height > 4 {
            viewModel.confirmSelection()
        } else {
            viewModel.selectionStart = nil
            viewModel.selectionRect = .zero
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let viewModel else { return }
        if viewModel.isWindowMode {
            viewModel.hoverWindows(at: point)
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        viewModel?.cancelSelection()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            viewModel?.cancelSelection()
        case 49: // Space
            viewModel?.isWindowMode.toggle()
        case 36, 76: // Return / Enter — optional confirm if a selection is waiting (unused for area auto-capture)
            viewModel?.confirmSelection()
        default:
            super.keyDown(with: event)
        }
    }

    private func updateTracking() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect,
            .enabledDuringMouseDrag
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
}

struct SelectionOverlayHost: NSViewRepresentable {
    @ObservedObject var viewModel: CaptureViewModel

    func makeNSView(context: Context) -> SelectionMouseView {
        let view = SelectionMouseView()
        view.viewModel = viewModel
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: SelectionMouseView, context: Context) {
        nsView.viewModel = viewModel
    }
}

// Kept for compatibility; overlay now embeds SelectionMouseView directly in AppKit.

@MainActor
final class OverlayWindowController {
    static let shared = OverlayWindowController()

    private(set) var overlayFrame: CGRect = .zero
    private var overlayWindow: SelectionOverlayWindow?
    private var editorWindow: NSWindow?
    private var countdownWindow: NSWindow?
    /// Esc / shortcuts must work even before the canvas receives focus (SwiftUI `.onKeyPress` alone is flaky).
    private var editorKeyMonitor: Any?
    private var editorCancelTextEdit: (() -> Bool)?

    func showSelectionOverlay(viewModel: CaptureViewModel) {
        closeOverlay()

        viewModel.selectionRect = .zero
        viewModel.selectionStart = nil
        viewModel.hoveredWindow = nil
        viewModel.isSelecting = true

        let frame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        overlayFrame = frame.isNull ? (NSScreen.main?.frame ?? .zero) : frame

        let window = SelectionOverlayWindow(
            contentRect: overlayFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.commonInit()

        let container = NSView(frame: CGRect(origin: .zero, size: overlayFrame.size))
        container.wantsLayer = true

        let visual = NSHostingView(
            rootView: SelectionOverlayView(viewModel: viewModel)
                .environmentObject(AppSettings.shared)
                .preferredColorScheme(AppSettings.shared.theme.colorScheme)
                .frame(width: overlayFrame.width, height: overlayFrame.height)
        )
        visual.frame = container.bounds
        visual.autoresizingMask = [.width, .height]

        let mouseView = SelectionMouseView(frame: container.bounds)
        mouseView.viewModel = viewModel
        mouseView.autoresizingMask = [.width, .height]

        // Visual behind, mouse catcher on top.
        container.addSubview(visual)
        container.addSubview(mouseView)

        window.contentView = container
        window.setFrame(overlayFrame, display: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(mouseView)
        NSApp.activate(ignoringOtherApps: true)

        overlayWindow = window
    }

    /// Converts a rect from SwiftUI overlay space (origin top-left) to global Cocoa (origin bottom-left).
    func globalCocoaRect(fromSwiftUI rect: CGRect) -> CGRect {
        let frame = overlayWindow?.frame ?? overlayFrame
        return CGRect(
            x: frame.origin.x + rect.origin.x,
            y: frame.origin.y + (frame.height - rect.origin.y - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    func globalCocoaPoint(fromSwiftUI point: CGPoint) -> CGPoint {
        let frame = overlayWindow?.frame ?? overlayFrame
        return CGPoint(
            x: frame.origin.x + point.x,
            y: frame.origin.y + (frame.height - point.y)
        )
    }

    /// Converts a global Cocoa rect (origin bottom-left) into SwiftUI overlay space (origin top-left).
    func swiftUIRect(fromGlobalCocoa rect: CGRect) -> CGRect {
        let frame = overlayWindow?.frame ?? overlayFrame
        return CGRect(
            x: rect.origin.x - frame.origin.x,
            y: frame.height - (rect.origin.y - frame.origin.y) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    func closeOverlay() {
        removeEditorKeyMonitor()
        editorCancelTextEdit = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    func showInPlaceEditor(image: NSImage, pinRect: CGRect, captureVM: CaptureViewModel) {
        closeEditor()
        removeEditorKeyMonitor()

        let annotationVM = AnnotationViewModel(image: image, canvasSize: pinRect.size)
        editorCancelTextEdit = { [weak annotationVM] in
            guard let annotationVM, annotationVM.isEditingText else { return false }
            annotationVM.cancelTextEdit()
            return true
        }

        let root = InPlaceEditorView(
            annotationVM: annotationVM,
            captureVM: captureVM,
            pinRect: pinRect
        )
        .environmentObject(AppSettings.shared)
        .preferredColorScheme(AppSettings.shared.theme.colorScheme)

        // Reuse / recreate the fullscreen overlay so editing happens where the capture was.
        if overlayWindow == nil {
            let frame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            overlayFrame = frame.isNull ? (NSScreen.main?.frame ?? .zero) : frame

            let window = SelectionOverlayWindow(
                contentRect: overlayFrame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.commonInit()
            overlayWindow = window
        }

        guard let window = overlayWindow else { return }
        window.appearance = AppSettings.shared.theme.resolvedWindowAppearance()

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: overlayFrame.size)
        window.contentView = hosting
        window.setFrame(overlayFrame, display: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hosting)
        NSApp.activate(ignoringOtherApps: true)
        installEditorKeyMonitor()
    }

    func closeInPlaceEditor(copyIfNeeded: Bool) {
        removeEditorKeyMonitor()
        editorCancelTextEdit = nil
        closeOverlay()
        closeEditor()
    }

    private func installEditorKeyMonitor() {
        removeEditorKeyMonitor()
        editorKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Escape — always dismiss editor (or cancel in-progress text edit).
            if event.keyCode == 53 {
                if self.editorCancelTextEdit?() == true {
                    return nil
                }
                self.closeInPlaceEditor(copyIfNeeded: false)
                return nil
            }
            return event
        }
    }

    private func removeEditorKeyMonitor() {
        if let editorKeyMonitor {
            NSEvent.removeMonitor(editorKeyMonitor)
            self.editorKeyMonitor = nil
        }
    }

    func showEditor(image: NSImage, viewModel: CaptureViewModel) {
        // Legacy window editor — redirect to in-place centered pin.
        let overlay = overlayFrame.isEmpty
            ? (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1200, height: 800))
            : overlayFrame
        // Convert main screen frame to swiftUI-ish top-left within overlay if needed.
        // For fullscreen captures, pin a fitted rect in the center of the overlay.
        let maxW = min(overlay.width * 0.72, 1100)
        let maxH = min(overlay.height * 0.72, 780)
        let aspect = max(image.size.width, 1) / max(image.size.height, 1)
        var width = maxW
        var height = width / aspect
        if height > maxH {
            height = maxH
            width = height * aspect
        }
        let pin = CGRect(
            x: (overlayFrame.width - width) / 2,
            y: (overlayFrame.height - height) / 2,
            width: width,
            height: height
        )
        showInPlaceEditor(image: image, pinRect: pin, captureVM: viewModel)
    }

    func closeEditor() {
        editorWindow?.orderOut(nil)
        editorWindow = nil
    }

    func showCountdown(_ seconds: Int, completion: @escaping () -> Void) {
        closeCountdown()
        let label = CountdownView(seconds: seconds) { [weak self] in
            self?.closeCountdown()
            completion()
        }
        let hosting = NSHostingView(rootView: label)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window
    }

    func closeCountdown() {
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
    }
}

private struct CountdownView: View {
    let seconds: Int
    let onFinished: () -> Void
    @State private var remaining: Int

    init(seconds: Int, onFinished: @escaping () -> Void) {
        self.seconds = seconds
        self.onFinished = onFinished
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        Text("\(remaining)")
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 140, height: 140)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            }
            .scaleEffect(remaining == seconds ? 0.85 : 1)
            .animation(.prismSpring, value: remaining)
            .onAppear {
                tick()
            }
    }

    private func tick() {
        guard remaining > 0 else {
            onFinished()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            remaining -= 1
            tick()
        }
    }
}

private extension NSView {
    func findSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for sub in subviews {
            if let found = sub.findSubview(ofType: type) {
                return found
            }
        }
        return nil
    }
}
