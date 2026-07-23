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

    func confirmSelection() {
        guard selectionRect.width > 4, selectionRect.height > 4 else { return }

        let pinRect = selectionRect
        let cocoaRect = overlay.globalCocoaRect(fromSwiftUI: selectionRect)

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
        withAnimation(.prismSoft) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            withAnimation(.prismSoft) {
                self?.toastMessage = nil
            }
        }
    }
}
