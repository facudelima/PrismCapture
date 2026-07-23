import SwiftUI

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .prismGlass(cornerRadius: cornerRadius)
    }
}

struct GlassIconButton: View {
    let systemName: String
    var help: String = ""
    var isSelected: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.18)
                                : Color.white.opacity(hovering ? 0.16 : 0.0)
                        )
                }
                .scaleEffect(hovering && !isDisabled ? 1.06 : 1)
                .animation(.prismSnappy, value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .prismGlass(cornerRadius: 14)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct OCRResultPanel: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.string("Detect Text"), systemImage: "text.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                GlassIconButton(systemName: "doc.on.doc", help: L10n.string("Copy text")) {
                    ClipboardService.shared.copyText(text)
                }
                GlassIconButton(systemName: "xmark", help: L10n.string("Close")) {
                    isPresented = false
                }
            }

            TextField(L10n.string("Search in text…"), text: $query)
                .textFieldStyle(.plain)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.08))
                }

            ScrollView {
                Text(highlightedText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
        }
        .padding(14)
        .frame(width: 320)
        .prismGlass(cornerRadius: 18)
    }

    private var highlightedText: AttributedString {
        var attributed = AttributedString(text.isEmpty ? L10n.string("No text detected.") : text)
        guard !query.isEmpty else { return attributed }
        let ns = NSString(string: text)
        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: query, options: .caseInsensitive, range: searchRange)
            if found.location == NSNotFound { break }
            if let range = Range(found, in: text),
               let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow.opacity(0.35)
            }
            let next = found.location + max(found.length, 1)
            if next >= ns.length { break }
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        return attributed
    }
}
