import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @State private var selection: ScreenshotItem.ID?

    private var filtered: [ScreenshotItem] {
        history.itemsMatching(ocrQuery: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            content
        }
        .background { VisualEffectBackground() }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Historial")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            TextField("Buscar OCR…", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 180)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.08))
                }
            Button("Vaciar") { history.clear() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Sin capturas")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { item in
                        HistoryCard(item: item) {
                            history.remove(item)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct HistoryCard: View {
    let item: ScreenshotItem
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.2))
                if let image = item.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 96)
                        .clipped()
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                if let fileURL = item.fileURL {
                    Button("Abrir") { NSWorkspace.shared.open(fileURL) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let remote = item.remoteURL, let url = URL(string: remote) {
                    Button("URL") {
                        ClipboardService.shared.copyURL(url)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(10)
        .prismGlass(cornerRadius: 16)
        .onHover { hovering = $0 }
        .onDrag {
            if let path = item.filePath {
                return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
    }
}
