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
        case .webp:
            type = (UTType(filenameExtension: "webp") ?? .png).identifier as CFString
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

    func flattened(annotations annotate: (CGContext, CGSize) -> Void) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        defer { output.unlockFocus() }
        self.draw(in: NSRect(origin: .zero, size: size))
        if let context = NSGraphicsContext.current?.cgContext {
            annotate(context, size)
        }
        return output
    }
}
