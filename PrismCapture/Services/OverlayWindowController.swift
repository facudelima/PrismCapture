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
/// Coordinates are converted to the global multi-screen overlay space (top-left origin).
final class SelectionMouseView: NSView {
    var viewModel: CaptureViewModel?
    /// Top-left of this screen inside the global overlay coordinate space.
    var screenOriginInOverlay: CGPoint = .zero
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
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Let SwiftUI receive clicks on the floating capture toolbar.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let viewModel, viewModel.isPointInToolbar(toGlobal(point)) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let point = toGlobal(convert(event.locationInWindow, from: nil))
        guard let viewModel else { return }

        // Always start a new selection drag (capture happens on mouse up via drag monitor).
        viewModel.dragKind = .creating
        viewModel.selectionStart = point
        viewModel.selectionRect = CGRect(origin: point, size: .zero)
        NSCursor.crosshair.set()
    }

    override func mouseDragged(with event: NSEvent) {
        // Handled by OverlayWindowController selection drag monitor (cross-screen safe).
    }

    override func mouseUp(with event: NSEvent) {
        // Handled by OverlayWindowController selection drag monitor (cross-screen safe).
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func rightMouseDown(with event: NSEvent) {
        viewModel?.cancelSelection()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            viewModel?.cancelSelection()
        case 36, 76: // Return / Enter
            viewModel?.confirmSelection()
        default:
            super.keyDown(with: event)
        }
    }

    private func toGlobal(_ local: CGPoint) -> CGPoint {
        CGPoint(x: screenOriginInOverlay.x + local.x, y: screenOriginInOverlay.y + local.y)
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

@MainActor
final class OverlayWindowController {
    static let shared = OverlayWindowController()

    /// Union of all screens in Cocoa coordinates (used for global overlay math).
    private(set) var overlayFrame: CGRect = .zero
    /// One borderless window per screen — required when displays differ in scale (Retina + 1080p).
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var editorWindow: NSWindow?
    private var countdownWindow: NSWindow?
    /// Esc / shortcuts must work even before the canvas receives focus (SwiftUI `.onKeyPress` alone is flaky).
    private var editorKeyMonitor: Any?
    private var editorCancelTextEdit: (() -> Bool)?
    /// Tracks drag across multiple per-screen windows (mouseDragged stays on the mouseDown window).
    private var selectionDragMonitor: Any?
    private weak var selectionViewModel: CaptureViewModel?

    func showSelectionOverlay(viewModel: CaptureViewModel) {
        closeOverlay()

        viewModel.selectionRect = .zero
        viewModel.selectionStart = nil
        viewModel.isSelecting = true
        selectionViewModel = viewModel

        overlayFrame = Self.screensUnionFrame()
        viewModel.overlaySize = overlayFrame.size

        var keyMouseView: SelectionMouseView?

        for screen in NSScreen.screens {
            let origin = screenOriginInOverlay(for: screen)
            let window = SelectionOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.commonInit()

            let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            container.wantsLayer = true

            let visual = NSHostingView(
                rootView: SelectionOverlayView(
                    viewModel: viewModel,
                    screenOriginInOverlay: origin
                )
                .environmentObject(AppSettings.shared)
                .preferredColorScheme(AppSettings.shared.theme.colorScheme)
                .frame(width: screen.frame.width, height: screen.frame.height)
            )
            visual.frame = container.bounds
            visual.autoresizingMask = [.width, .height]

            let mouseView = SelectionMouseView(frame: container.bounds)
            mouseView.viewModel = viewModel
            mouseView.screenOriginInOverlay = origin
            mouseView.autoresizingMask = [.width, .height]

            container.addSubview(visual)
            container.addSubview(mouseView)

            window.contentView = container
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            overlayWindows.append(window)
            if screen == NSScreen.main || keyMouseView == nil {
                keyMouseView = mouseView
            }
        }

        if let keyWindow = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first {
            keyWindow.makeKeyAndOrderFront(nil)
            if let keyMouseView {
                keyWindow.makeFirstResponder(keyMouseView)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        installSelectionDragMonitor()
    }

    /// Converts `NSEvent.mouseLocation` (Cocoa global) into overlay top-left space.
    func overlayPointFromMouseLocation(_ cocoaPoint: CGPoint = NSEvent.mouseLocation) -> CGPoint {
        CGPoint(
            x: cocoaPoint.x - overlayFrame.minX,
            y: overlayFrame.maxY - cocoaPoint.y
        )
    }

    private func installSelectionDragMonitor() {
        removeSelectionDragMonitor()
        selectionDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, let vm = self.selectionViewModel else { return event }
            let point = self.overlayPointFromMouseLocation()
            switch event.type {
            case .leftMouseDragged:
                guard vm.dragKind == .creating || vm.dragKind == .moving else { return event }
                vm.handleSelectionMouseDragged(at: point)
                return nil
            case .leftMouseUp:
                guard vm.dragKind == .creating || vm.dragKind == .moving else { return event }
                vm.handleSelectionMouseDragged(at: point)
                vm.dragKind = .none
                if vm.selectionRect.width > 4, vm.selectionRect.height > 4 {
                    vm.confirmSelection()
                } else {
                    vm.selectionStart = nil
                    vm.selectionRect = .zero
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeSelectionDragMonitor() {
        if let selectionDragMonitor {
            NSEvent.removeMonitor(selectionDragMonitor)
            self.selectionDragMonitor = nil
        }
    }

    /// Top-left of `screen` inside the global overlay (top-left origin) coordinate space.
    func screenOriginInOverlay(for screen: NSScreen) -> CGPoint {
        CGPoint(
            x: screen.frame.minX - overlayFrame.minX,
            y: overlayFrame.maxY - screen.frame.maxY
        )
    }

    /// Converts a rect from SwiftUI overlay space (origin top-left) to global Cocoa (origin bottom-left).
    func globalCocoaRect(fromSwiftUI rect: CGRect) -> CGRect {
        let frame = overlayFrame
        return CGRect(
            x: frame.origin.x + rect.origin.x,
            y: frame.origin.y + (frame.height - rect.origin.y - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    func globalCocoaPoint(fromSwiftUI point: CGPoint) -> CGPoint {
        let frame = overlayFrame
        return CGPoint(
            x: frame.origin.x + point.x,
            y: frame.origin.y + (frame.height - point.y)
        )
    }

    /// Converts a global Cocoa rect (origin bottom-left) into SwiftUI overlay space (origin top-left).
    func swiftUIRect(fromGlobalCocoa rect: CGRect) -> CGRect {
        let frame = overlayFrame
        return CGRect(
            x: rect.origin.x - frame.origin.x,
            y: frame.height - (rect.origin.y - frame.origin.y) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    func closeOverlay() {
        removeEditorKeyMonitor()
        removeSelectionDragMonitor()
        editorCancelTextEdit = nil
        selectionViewModel = nil
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    func showInPlaceEditor(
        image: NSImage,
        pinRect: CGRect,
        captureVM: CaptureViewModel,
        allowsPinMove: Bool = true
    ) {
        // Convert while overlayFrame still matches pinRect's coordinate space.
        let cocoaPin = globalCocoaRect(fromSwiftUI: pinRect)

        closeEditor()
        removeEditorKeyMonitor()
        closeOverlay()

        // Pin the editor on the screen that contains the capture (avoids Retina/1080p span bugs).
        let screen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: cocoaPin.midX, y: cocoaPin.midY))
        } ?? CaptureService.shared.screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else { return }

        overlayFrame = screen.frame
        let localPin = swiftUIRect(fromGlobalCocoa: cocoaPin)

        let annotationVM = AnnotationViewModel(image: image, canvasSize: localPin.size)
        editorCancelTextEdit = { [weak annotationVM] in
            guard let annotationVM, annotationVM.isEditingText else { return false }
            annotationVM.cancelTextEdit()
            return true
        }

        let root = InPlaceEditorView(
            annotationVM: annotationVM,
            captureVM: captureVM,
            pinRect: localPin,
            allowsPinMove: allowsPinMove
        )
        .environmentObject(AppSettings.shared)
        .preferredColorScheme(AppSettings.shared.theme.colorScheme)

        let window = SelectionOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.commonInit()
        window.appearance = AppSettings.shared.theme.resolvedWindowAppearance()

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        window.contentView = hosting
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hosting)
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows = [window]
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
        let screen = CaptureService.shared.screenUnderMouse() ?? NSScreen.main
        overlayFrame = screen?.frame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)

        let maxW = min(overlayFrame.width * 0.72, 1100)
        let maxH = min(overlayFrame.height * 0.72, 780)
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
        // Fullscreen capture: pin is a preview frame — never allow Lightshot-style pan/recapture.
        showInPlaceEditor(image: image, pinRect: pin, captureVM: viewModel, allowsPinMove: false)
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
        if let screen = CaptureService.shared.screenUnderMouse() {
            let f = screen.frame
            window.setFrameOrigin(NSPoint(
                x: f.midX - 80,
                y: f.midY - 80
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window
    }

    func closeCountdown() {
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
    }

    private static func screensUnionFrame() -> CGRect {
        let frame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return frame.isNull ? (NSScreen.main?.frame ?? .zero) : frame
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
