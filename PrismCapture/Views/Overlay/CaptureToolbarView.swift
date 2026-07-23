import SwiftUI

struct CaptureToolbarView: View {
    @ObservedObject var viewModel: CaptureViewModel

    var body: some View {
        HStack(spacing: 2) {
            GlassIconButton(systemName: "checkmark", help: L10n.string("Capture (Return)")) {
                viewModel.confirmSelection()
            }
            GlassIconButton(systemName: "xmark", help: L10n.string("Cancel (Esc)")) {
                viewModel.cancelSelection()
            }

            sizeLabel
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .prismGlass(cornerRadius: 16)
        .animation(.prismSpring, value: viewModel.selectionRect)
    }

    private var sizeLabel: some View {
        Text("\(Int(viewModel.selectionRect.width)) × \(Int(viewModel.selectionRect.height))")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .monospacedDigit()
    }
}
