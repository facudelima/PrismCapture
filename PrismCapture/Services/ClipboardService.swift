import AppKit
import UniformTypeIdentifiers

@MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
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
