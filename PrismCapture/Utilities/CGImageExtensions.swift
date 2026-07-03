import CoreGraphics
import AppKit
import CoreImage

extension CGImage {
    func pixelated(blockSize: Int = 12) -> CGImage? {
        let width = self.width
        let height = self.height
        let smallW = max(1, width / max(blockSize, 1))
        let smallH = max(1, height / max(blockSize, 1))

        guard let smallContext = CGContext(
            data: nil,
            width: smallW,
            height: smallH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        smallContext.interpolationQuality = .medium
        smallContext.draw(self, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let small = smallContext.makeImage() else { return nil }

        guard let fullContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        fullContext.interpolationQuality = .none
        fullContext.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))
        return fullContext.makeImage()
    }

    func blurred(radius: Double = 12) -> CGImage? {
        let input = CIImage(cgImage: self)
        let filtered = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(filtered, from: input.extent)
    }
}
