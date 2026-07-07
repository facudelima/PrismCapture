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

    func savePanel(image: NSImage, format: ImageFormat) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .png]
        panel.nameFieldStringValue = makeFilename(format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            guard let data = image.data(using: format) else { return nil }
            try data.write(to: url, options: .atomic)
            return url
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
