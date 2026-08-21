import AppKit
import SwiftUI
import Combine

enum SelectionDragKind {
    case none
    case creating
    case moving
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var mode: CaptureMode = .area
    @Published var delay: CaptureDelay = .none
    @Published var isSelecting = false
    @Published var selectionRect: CGRect = .zero
    @Published var selectionStart: CGPoint?
    @Published var toastMessage: String?
    @Published var dragKind: SelectionDragKind = .none

    /// Overlay size in SwiftUI points (for clamping / toolbar hit tests).
    var overlaySize: CGSize = .zero

    private var moveGrabOffset: CGSize = .zero
    private let captureService = CaptureService.shared
    private let clipboard = ClipboardService.shared
    private let files = FileService.shared
    private let overlay = OverlayWindowController.shared

    func start(mode: CaptureMode, delay: CaptureDelay = .none) {
        self.mode = mode
        self.delay = delay
        selectionRect = .zero
        selectionStart = nil
        dragKind = .none

        Task { @MainActor in
            let allowed = await PermissionService.shared.ensureScreenRecordingPermission()
            guard allowed else {
                PermissionService.shared.openScreenRecordingSettings()
                showToast(L10n.string("Screen permission missing — check Settings and relaunch the app"))
                return
            }
            beginCaptureFlow(mode: mode, delay: delay)
        }
    }

    private func beginCaptureFlow(mode: CaptureMode, delay: CaptureDelay) {
        NSApp.activate(ignoringOtherApps: true)

        let run = { [weak self] in
            guard let self else { return }
            switch mode {
            case .fullscreen:
                Task { await self.captureFullscreen() }
            case .area, .delayed:
                self.isSelecting = true
                self.overlay.showSelectionOverlay(viewModel: self)
            }
        }

        if delay != .none && mode == .fullscreen {
            overlay.showCountdown(delay.rawValue, completion: run)
        } else if delay != .none && mode != .area {
            overlay.showCountdown(delay.rawValue, completion: run)
        } else {
            run()
        }
    }

    func cancelSelection() {
        isSelecting = false
        selectionRect = .zero
        selectionStart = nil
        dragKind = .none
        overlay.closeOverlay()
    }

    // MARK: - Selection create / move

    func handleSelectionMouseDown(at point: CGPoint) {
        if selectionRect.width > 4, selectionRect.height > 4, selectionRect.contains(point) {
            dragKind = .moving
            moveGrabOffset = CGSize(
                width: point.x - selectionRect.origin.x,
                height: point.y - selectionRect.origin.y
            )
            return
        }
        dragKind = .creating
        selectionStart = point
        selectionRect = CGRect(origin: point, size: .zero)
    }

    func handleSelectionMouseDragged(at point: CGPoint) {
        switch dragKind {
        case .creating:
            guard let start = selectionStart else { return }
            selectionRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
        case .moving:
            var next = CGRect(
                x: point.x - moveGrabOffset.width,
                y: point.y - moveGrabOffset.height,
                width: selectionRect.width,
                height: selectionRect.height
            )
            next = clamp(next, in: overlaySize)
            selectionRect = next
            selectionStart = next.origin
        case .none:
            break
        }
    }

    func handleSelectionMouseUp(at point: CGPoint) {
        switch dragKind {
        case .creating:
            handleSelectionMouseDragged(at: point)
            if selectionRect.width <= 4 || selectionRect.height <= 4 {
                selectionStart = nil
                selectionRect = .zero
            }
            // Keep selection active — confirm with ✔︎ / Enter.
        case .moving:
            handleSelectionMouseDragged(at: point)
        case .none:
            break
        }
        dragKind = .none
    }

    func isPointInSelection(_ point: CGPoint) -> Bool {
        selectionRect.width > 4 && selectionRect.height > 4 && selectionRect.contains(point)
    }

    /// Approximate toolbar hit area under the selection (matches SelectionOverlayView layout).
    func isPointInToolbar(_ point: CGPoint) -> Bool {
        guard selectionRect.width > 4, selectionRect.height > 4 else { return false }
        let size = overlaySize
        guard size.width > 0, size.height > 0 else { return false }
        let toolbarSize = CGSize(width: 220, height: 44)
        let center = toolbarCenter(in: size)
        let frame = CGRect(
            x: center.x - toolbarSize.width / 2,
            y: center.y - toolbarSize.height / 2,
            width: toolbarSize.width,
            height: toolbarSize.height
        ).insetBy(dx: -6, dy: -6)
        return frame.contains(point)
    }

    func toolbarCenter(in size: CGSize) -> CGPoint {
        let rect = selectionRect
        let below = rect.maxY + 36
        let above = rect.minY - 36
        let y: CGFloat
        if below < size.height - 40 {
            y = below
        } else if above > 40 {
            y = above
        } else {
            y = min(max(rect.midY, 40), size.height - 40)
        }
        return CGPoint(x: min(max(rect.midX, 80), size.width - 80), y: y)
    }

    private func clamp(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        var r = rect
        r.origin.x = min(max(0, r.origin.x), max(0, size.width - r.width))
        r.origin.y = min(max(0, r.origin.y), max(0, size.height - r.height))
        return r
    }

    /// Backing scale of the display the rect sits on (overlay space is multi-monitor).
    func backingScale(for rect: CGRect) -> CGFloat {
        let cocoa = overlay.globalCocoaRect(fromSwiftUI: rect)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
    }

    /// Snaps a selection to whole device pixels.
    ///
    /// A drag produces fractional point coordinates, but the capture is rounded to an integer
    /// pixel count. The in-place editor then pins that bitmap back at the fractional origin, so
    /// source and destination disagree by a subpixel and the whole preview gets resampled —
    /// visibly softer than the live screen showing through around it. Snapping first makes the
    /// pinned bitmap land 1:1 on the pixel grid.
    /// Pass `within` to keep the snapped rect inside the overlay: rounding can otherwise push
    /// an edge-hugging selection a fraction of a point off-screen, and the capture's intersection
    /// with the display would trim it back to a fractional size — undoing the alignment.
    static func pixelAligned(_ rect: CGRect, scale: CGFloat, within bounds: CGSize? = nil) -> CGRect {
        let scale = scale > 0 ? scale : 1
        let snap = { (value: CGFloat) in (value * scale).rounded() / scale }
        let step = 1 / scale
        var minX = snap(rect.minX)
        var minY = snap(rect.minY)
        let width = max(snap(rect.maxX) - minX, step)
        let height = max(snap(rect.maxY) - minY, step)

        if let bounds, bounds.width > 0, bounds.height > 0 {
            // Bounds come from a screen frame, so snapping them keeps the grid alignment.
            minX = min(max(0, minX), max(0, snap(bounds.width) - width))
            minY = min(max(0, minY), max(0, snap(bounds.height) - height))
        }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    func confirmSelection() {
        guard selectionRect.width > 4, selectionRect.height > 4 else { return }

        let pinRect = Self.pixelAligned(selectionRect, scale: backingScale(for: selectionRect), within: overlaySize)
        selectionRect = pinRect
        let cocoaRect = overlay.globalCocoaRect(fromSwiftUI: pinRect)

        let captureBlock = { [weak self] in
            guard let self else { return }
            Task {
                do {
                    // Overlay stays up; SCContentFilter excludes PrismCapture windows,
                    // so we don't need to hide + wait before capturing.
                    let image = try await self.captureService.captureRectInGlobalCocoa(cocoaRect)
                    self.finish(with: image, pinRect: pinRect)
                } catch {
                    self.showToast(error.localizedDescription)
                    self.cancelSelection()
                }
            }
        }

        if delay != .none {
            overlay.closeOverlay()
            overlay.showCountdown(delay.rawValue, completion: captureBlock)
        } else {
            captureBlock()
        }
    }

    func captureFullscreen() async {
        do {
            let image = try await captureService.captureFullscreen()
            finish(with: image, pinRect: nil)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func finish(with image: NSImage, pinRect: CGRect?) {
        isSelecting = false
        selectionStart = nil
        dragKind = .none

        let settings = AppSettings.shared

        if settings.autoSave {
            do {
                let url = try files.save(image, format: settings.imageFormat)
                HistoryViewModel.shared.add(image: image, fileURL: url)
                if settings.clipboardBehavior == .copyOnSave {
                    clipboard.copyImage(image)
                }
            } catch {
                showToast(error.localizedDescription)
            }
        }

        if let pinRect, pinRect.width > 4, pinRect.height > 4 {
            overlay.showInPlaceEditor(image: image, pinRect: pinRect, captureVM: self)
        } else {
            overlay.showEditor(image: image, viewModel: self)
        }
    }

    func showToast(_ message: String) {
        // Callers include copy/save actions fired from onKeyPress/Button handlers under
        // .focused() — starting a `withAnimation` transaction synchronously from there
        // re-enters SwiftUI's update pipeline and triggers "Publishing changes from
        // within view updates". Deferring one tick keeps the transaction outside it.
        DispatchQueue.main.async { [weak self] in
            withAnimation(.prismSoft) {
                self?.toastMessage = message
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            withAnimation(.prismSoft) {
                self?.toastMessage = nil
            }
        }
    }
}
