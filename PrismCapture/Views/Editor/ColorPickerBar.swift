import SwiftUI
import AppKit

struct ColorPickerBar: View {
    @Binding var color: Color
    @State private var selectedIndex: Int = 0

    private let swatches: [Color] = [
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink, .white, .black
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { index, swatch in
                Button {
                    selectedIndex = index
                    color = swatch
                } label: {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    .white.opacity(selectedIndex == index ? 0.95 : 0.25),
                                    lineWidth: selectedIndex == index ? 2 : 0.5
                                )
                        }
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
                .help("Color")
            }
        }
        .onAppear {
            // Default swatch highlight (red) without re-assigning color every redraw.
            selectedIndex = 0
        }
    }
}
