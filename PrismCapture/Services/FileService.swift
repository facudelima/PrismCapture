import AppKit
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class FileService {
    static let shared = FileService()

    func ensureSaveFolder(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func makeFilename(format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "PrismCapture \(formatter.string(from: Date())).\(format.fileExtension)"
    }

    func save(_ image: NSImage, to folder: URL? = nil, format: ImageFormat = .png) throws -> URL {
        let settings = AppSettings.shared
        let destinationFolder = folder ?? settings.resolvedSaveFolder
        try ensureSaveFolder(destinationFolder)

        let url = destinationFolder.appendingPathComponent(makeFilename(format: format))
        guard let data = image.data(using: format) else {
            throw FileServiceError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Shows the panel first and only renders/encodes the image once the user actually
    /// confirms a destination — rendering (and flattening annotations) upfront added a
    /// visible delay before the dialog appeared, for no benefit if the user cancels.
    func savePanel(format: ImageFormat, image: () -> NSImage) -> (url: URL, image: NSImage)? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .png]
        panel.nameFieldStringValue = makeFilename(format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        // The editor overlay sits at `.screenSaver` level; without this the panel
        // opens behind it and is invisible/unreachable.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let renderedImage = image()
        do {
            guard let data = renderedImage.data(using: format) else { return nil }
            try data.write(to: url, options: .atomic)
            return (url, renderedImage)
        } catch {
            return nil
        }
    }
}

enum FileServiceError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "No se pudo codificar la imagen."
    }
}
