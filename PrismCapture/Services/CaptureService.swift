import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    func captureFullscreen(display: NSScreen? = NSScreen.main) async throws -> NSImage {
        guard let display else { throw CaptureError.noDisplay }
        return try await captureRectInGlobalCocoa(display.frame)
    }

    /// Captures a rectangle in **global Cocoa coordinates** (origin at bottom-left).
    func captureRectInGlobalCocoa(_ rect: CGRect) async throws -> NSImage {
        try await captureWithScreenCaptureKit(globalCocoaRect: rect)
    }

    func captureWindow(windowID: CGWindowID) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.captureFailed
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = backingScale(forGlobalRect: window.frame)
        let pixelSize = safePixelSize(width: window.frame.width, height: window.frame.height, scale: scale)

        let config = SCStreamConfiguration()
        config.width = pixelSize.width
        config.height = pixelSize.height
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    func listWindows() async -> [(id: CGWindowID, name: String, bounds: CGRect)] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return content.windows.compactMap { window in
                guard window.isOnScreen,
                      window.frame.width > 1,
                      window.frame.height > 1,
                      window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                else { return nil }

                let appName = window.owningApplication?.applicationName ?? "Ventana"
                let title = (window.title?.isEmpty == false) ? window.title! : appName
                return (window.windowID, title, window.frame)
            }
        } catch {
            return listWindowsLegacy()
        }
    }

    // MARK: - ScreenCaptureKit

    private func captureWithScreenCaptureKit(globalCocoaRect: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let fallback = content.displays.first else { throw CaptureError.noDisplay }

        let selectedDisplay = content.displays.first { $0.frame.intersects(globalCocoaRect) } ?? fallback
        let displayFrame = selectedDisplay.frame
        let intersection = globalCocoaRect.intersection(displayFrame)

        guard !intersection.isNull,
              intersection.width.isFinite,
              intersection.height.isFinite,
              intersection.width >= 1,
              intersection.height >= 1
        else {
            throw CaptureError.invalidRegion
        }

        // sourceRect is display-local with origin at the top-left.
        let sourceRect = CGRect(
            x: intersection.minX - displayFrame.minX,
            y: displayFrame.maxY - intersection.maxY,
            width: intersection.width,
            height: intersection.height
        )

        let scale = backingScale(forDisplayID: selectedDisplay.displayID)
        let pixelSize = safePixelSize(width: sourceRect.width, height: sourceRect.height, scale: scale)

        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: selectedDisplay, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        config.width = pixelSize.width
        config.height = pixelSize.height
        config.sourceRect = sourceRect
        config.scalesToFit = false
        config.showsCursor = false
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    // MARK: - Helpers

    private func safePixelSize(width: CGFloat, height: CGFloat, scale: CGFloat) -> (width: Int, height: Int) {
        let rawW = (width * scale).rounded(.toNearestOrAwayFromZero)
        let rawH = (height * scale).rounded(.toNearestOrAwayFromZero)

        guard rawW.isFinite, rawH.isFinite, rawW > 0, rawH > 0 else {
            return (1, 1)
        }

        // Avoid trapping Int(Double) → "Not enough bits to represent the passed value"
        let maxDimension: CGFloat = 16_384
        let clampedW = min(max(rawW, 1), maxDimension)
        let clampedH = min(max(rawH, 1), maxDimension)
        return (Int(clampedW), Int(clampedH))
    }

    private func backingScale(forDisplayID displayID: CGDirectDisplayID) -> CGFloat {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(number.uint32Value) == displayID {
                return screen.backingScaleFactor
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }

    private func backingScale(forGlobalRect rect: CGRect) -> CGFloat {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
    }

    /// Metadata-only fallback (not used for bitmap capture).
    private func listWindowsLegacy() -> [(id: CGWindowID, name: String, bounds: CGRect)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return info.compactMap { entry in
            guard
                let id = entry[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                let owner = entry[kCGWindowOwnerName as String] as? String,
                owner != "PrismCapture",
                let layer = entry[kCGWindowLayer as String] as? Int,
                layer == 0
            else { return nil }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            let name = (entry[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? owner
            return (id, name, bounds)
        }
    }
}

enum CaptureError: LocalizedError {
    case noDisplay
    case captureFailed
    case permissionDenied
    case invalidRegion

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No se encontró una pantalla."
        case .captureFailed: return "No se pudo capturar la pantalla."
        case .permissionDenied: return "Permiso de grabación de pantalla denegado."
        case .invalidRegion: return "La región de captura no es válida."
        }
    }
}
