import Foundation
import AppKit
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    static let shared = HistoryViewModel()

    @Published private(set) var items: [ScreenshotItem] = []

    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("PrismCapture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        load()
    }

    func add(image: NSImage, fileURL: URL?, remoteURL: URL? = nil, ocrText: String? = nil) {
        let item = ScreenshotItem(
            filePath: fileURL?.path,
            remoteURL: remoteURL?.absoluteString,
            ocrText: ocrText,
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
        items.insert(item, at: 0)
        if items.count > 100 {
            items = Array(items.prefix(100))
        }
        save()
    }

    func remove(_ item: ScreenshotItem) {
        items.removeAll { $0.id == item.id }
        if let path = item.filePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        save()
    }

    func clear() {
        for item in items {
            if let path = item.filePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        items.removeAll()
        save()
    }

    func itemsMatching(ocrQuery: String) -> [ScreenshotItem] {
        guard !ocrQuery.isEmpty else { return items }
        return items.filter { ($0.ocrText ?? "").localizedCaseInsensitiveContains(ocrQuery) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ScreenshotItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
