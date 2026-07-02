import Foundation
import AppKit

struct ScreenshotItem: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var filePath: String?
    var remoteURL: String?
    var ocrText: String?
    var width: Int
    var height: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        filePath: String? = nil,
        remoteURL: String? = nil,
        ocrText: String? = nil,
        width: Int = 0,
        height: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.filePath = filePath
        self.remoteURL = remoteURL
        self.ocrText = ocrText
        self.width = width
        self.height = height
    }

    var fileURL: URL? {
        guard let filePath else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    var thumbnail: NSImage? {
        guard let fileURL else { return nil }
        return NSImage(contentsOf: fileURL)
    }
}
