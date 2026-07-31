import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
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

    func cropped(to rect: CGRect) -> NSImage? {
        guard let cgImage else { return nil }
        let scaleX = CGFloat(cgImage.width) / size.width
        let scaleY = CGFloat(cgImage.height) / size.height
        let scaled = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let cropped = cgImage.cropping(to: scaled) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    /// Renders annotations onto a copy of this image via a raw `CGContext` sized to the
    /// source's actual pixel dimensions. `NSImage.lockFocus()` sizes its offscreen buffer
    /// using the *point* size and the screen's `backingScaleFactor`, but our captured images
    /// already carry pixel counts as their `size` (see `CaptureService`), so on Retina
    /// displays `lockFocus` doubled that again — a full-screen capture ballooned into a
    /// buffer ~4x its real pixel count, making flatten (and the clipboard copy after it)
    /// extremely slow.
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
        return NSImage(cgImage: outputCGImage, size: size)
    }
}
