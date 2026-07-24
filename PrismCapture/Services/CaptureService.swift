import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    func captureFullscreen(display: NSScreen? = nil) async throws -> NSImage {
        let screen = display ?? screenUnderMouse() ?? NSScreen.main
        guard let screen else { throw CaptureError.noDisplay }
        return try await captureRectInGlobalCocoa(screen.frame)
    }

    /// Screen that currently contains the mouse pointer (multi-monitor aware).
    func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
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
        guard !content.displays.isEmpty else { throw CaptureError.noDisplay }

        // Map via NSScreen + displayID. Never intersect SCDisplay.frame (Quartz) with Cocoa rects.
        guard let screen = bestScreen(for: globalCocoaRect) else {
            throw CaptureError.noDisplay
        }

        let selectedDisplay: SCDisplay
        if let id = displayID(for: screen),
           let match = content.displays.first(where: { $0.displayID == id }) {
            selectedDisplay = match
        } else if let fallback = content.displays.first {
            selectedDisplay = fallback
        } else {
            throw CaptureError.noDisplay
        }

        let screenFrame = screen.frame
        let intersection = globalCocoaRect.intersection(screenFrame)

        guard !intersection.isNull,
              intersection.width.isFinite,
              intersection.height.isFinite,
              intersection.width >= 1,
              intersection.height >= 1
        else {
            throw CaptureError.invalidRegion
        }

        // Display-local crop in points, origin at the top-left of this screen.
        let cropPoints = CGRect(
            x: intersection.minX - screenFrame.minX,
            y: screenFrame.maxY - intersection.maxY,
            width: intersection.width,
            height: intersection.height
        )

        let scale = screen.backingScaleFactor
        let fullPixel = safePixelSize(width: screenFrame.width, height: screenFrame.height, scale: scale)

        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: selectedDisplay, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        // Capture the whole display, then crop — avoids fragile SCStream sourceRect
        // across mixed-DPI layouts (Retina laptop + 1080p external).
        config.width = fullPixel.width
        config.height = fullPixel.height
        config.scalesToFit = false
        config.showsCursor = false
        config.captureResolution = .best

        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let isFullScreen = abs(cropPoints.width - screenFrame.width) < 0.5
            && abs(cropPoints.height - screenFrame.height) < 0.5
            && abs(cropPoints.minX) < 0.5
            && abs(cropPoints.minY) < 0.5

        let cgImage: CGImage
        if isFullScreen {
            cgImage = fullImage
        } else {
            let pixelCrop = CGRect(
                x: (cropPoints.minX * scale).rounded(.towardZero),
                y: (cropPoints.minY * scale).rounded(.towardZero),
                width: (cropPoints.width * scale).rounded(.toNearestOrAwayFromZero),
                height: (cropPoints.height * scale).rounded(.toNearestOrAwayFromZero)
            ).integral

            let clamped = pixelCrop.intersection(
                CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)
            )
            guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
                  let cropped = fullImage.cropping(to: clamped)
            else {
                throw CaptureError.invalidRegion
            }
            cgImage = cropped
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    // MARK: - Helpers

    /// Picks the NSScreen that covers the most of `rect` (Cocoa global coordinates).
    private func bestScreen(for rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let exact = screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) {
            return exact
        }

        return screens.max { a, b in
            intersectionArea(rect, a.frame) < intersectionArea(rect, b.frame)
        }
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        return i.width * i.height
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

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

    private func backingScale(forGlobalRect rect: CGRect) -> CGFloat {
        bestScreen(for: rect)?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
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
