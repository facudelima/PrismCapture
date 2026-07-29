import AppKit
import UniformTypeIdentifiers

@MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Plain `writeObjects([image])` only declares an uncompressed TIFF
        // representation (tens of MB for a real screenshot). Clipboard
        // managers that cap how much they store/restore per item silently
        // drop or fail to round-trip that, so paste-from-history only works
        // once. Declare a compressed PNG explicitly (plus TIFF as a
        // fallback for readers that don't understand PNG).
        let item = NSPasteboardItem()
        var didSetType = false
        if let pngData = image.data(using: .png) {
            item.setData(pngData, forType: .png)
            didSetType = true
        }
        if let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
            didSetType = true
        }

        if didSetType {
            pasteboard.writeObjects([item])
        } else {
            pasteboard.writeObjects([image])
        }
    }

    func copyFile(at url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyURL(_ url: URL) {
        copyText(url.absoluteString)
    }
}
