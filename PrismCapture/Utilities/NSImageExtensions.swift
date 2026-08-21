import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension NSImage {
    /// Full-resolution bitmap backing this image.
    ///
    /// Goes through the representations first on purpose: `cgImage(forProposedRect:context:hints:)`
    /// resolves the proposed rect against a 1x device when `context` is nil, so on a 2x capture
    /// (whose `size` is in points) it can hand back a downscaled copy — which would silently halve
    /// the resolution of every save, copy and upload.
    var cgImage: CGImage? {
        let widest = representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let cg = widest?.cgImage {
            return cg
        }
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Real bitmap dimensions in device pixels. `size` is in *points*, so on Retina it is
    /// half of this — every export, crop and annotation-scaling math must use this instead.
    var pixelSize: CGSize {
        let widest = representations.map(\.pixelsWide).max() ?? 0
        let tallest = representations.map(\.pixelsHigh).max() ?? 0
        guard widest > 0, tallest > 0 else { return size }
        return CGSize(width: widest, height: tallest)
    }

    /// Wraps a CGImage keeping its backing scale honest: `size` ends up in points and the
    /// representation keeps the full pixel count. Building the image with the pixel count as
    /// its point size instead (the obvious `NSImage(cgImage:size:)`) makes AppKit treat a 2x
    /// capture as a 1x image, so drawing it at its natural on-screen size resamples the whole
    /// bitmap and the preview looks softer than the screen behind it.
    static func fromCGImage(_ cgImage: CGImage, scale: CGFloat) -> NSImage {
        let scale = scale > 0 ? scale : 1
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let pointSize = NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        rep.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }

    func data(using format: ImageFormat, compression: Double = 0.92) -> Data? {
        guard let cgImage else { return nil }
        let mutable = NSMutableData()
        let type: CFString
        switch format {
        case .png:
            type = UTType.png.identifier as CFString
        case .jpeg:
            type = UTType.jpeg.identifier as CFString
        }

        guard let destination = CGImageDestinationCreateWithData(mutable, type, 1, nil) else {
            return nil
        }

        var props: [CFString: Any] = [:]
        if format == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = compression
        }
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
    }

    /// `rect` is in points (same space as `size`).
    func cropped(to rect: CGRect) -> NSImage? {
        guard let cgImage, size.width > 0, size.height > 0 else { return nil }
        let scaleX = CGFloat(cgImage.width) / size.width
        let scaleY = CGFloat(cgImage.height) / size.height
        let scaled = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let cropped = cgImage.cropping(to: scaled) else { return nil }
        return .fromCGImage(cropped, scale: scaleX)
    }

    /// Renders annotations onto a copy of this image via a raw `CGContext` sized to the
    /// source's actual pixel dimensions, and hands back a result with the same backing scale.
    /// `NSImage.lockFocus()` is avoided here: it sizes its offscreen buffer from the *point*
    /// size times the screen's `backingScaleFactor`, which is the current display's scale and
    /// not necessarily the one the capture came from — on a mixed Retina/1080p setup that
    /// silently rescales the bitmap, and it used to balloon full-screen captures into a buffer
    /// ~4x their real pixel count, making flatten (and the clipboard copy after it) very slow.
    func flattened(annotations annotate: (CGContext, CGSize) -> Void) -> NSImage {
        guard let cgImage else { return self }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        annotate(context, CGSize(width: width, height: height))

        guard let outputCGImage = context.makeImage() else { return self }
        let scale = size.width > 0 ? CGFloat(width) / size.width : 1
        return .fromCGImage(outputCGImage, scale: scale)
    }
}
