import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: AnnotationViewModel
    @ObservedObject var captureVM: CaptureViewModel
    @EnvironmentObject private var settings: AppSettings
    var compact: Bool = false

    private let tools: [EditorTool] = [
        .rectangle, .circle, .arrow, .line, .pencil, .highlighter,
        .blur, .pixelate, .text, .marker
    ]

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(tools) { tool in
                GlassIconButton(
                    systemName: tool.systemImage,
                    help: tool.title,
                    isSelected: viewModel.selectedTool == tool
                ) {
                    if viewModel.isEditingText {
                        viewModel.commitTextEdit()
                    }
                    viewModel.selectedTool = tool
                }
            }

            toolbarDivider

            ColorPickerBar(color: $viewModel.strokeColor)

            if !compact {
                ForEach(StrokeWidth.allCases) { width in
                    GlassIconButton(
                        systemName: "circle.fill",
                        help: L10n.format("Stroke width %lld", Int(width.rawValue)),
                        isSelected: viewModel.strokeWidth == width
                    ) {
                        viewModel.strokeWidth = width
                    }
                    .scaleEffect(0.55 + width.rawValue / 30)
                }

                toolbarDivider
            }

            GlassIconButton(systemName: "arrow.uturn.backward", help: L10n.string("Undo"), isDisabled: !viewModel.canUndo) {
                viewModel.undo()
            }
            GlassIconButton(systemName: "arrow.uturn.forward", help: L10n.string("Redo"), isDisabled: !viewModel.canRedo) {
                viewModel.redo()
            }

            toolbarDivider

            GlassIconButton(
                systemName: viewModel.isOCRLoading ? "ellipsis" : "text.viewfinder",
                help: L10n.string("Detect Text"),
                isDisabled: viewModel.isOCRLoading
            ) {
                Task { await viewModel.runOCR() }
            }

            GlassIconButton(systemName: "doc.on.doc", help: L10n.string("Copy (⌘C)")) {
                ClipboardService.shared.copyImage(viewModel.renderedImage())
                if settings.showToastOnCopy {
                    captureVM.showToast(L10n.string("Copied to clipboard"))
                }
                OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
            }
            GlassIconButton(systemName: "square.and.arrow.down", help: L10n.string("Save (⌘S)")) {
                if let url = FileService.shared.savePanel(image: viewModel.renderedImage(), format: settings.imageFormat) {
                    HistoryViewModel.shared.add(
                        image: viewModel.renderedImage(),
                        fileURL: url,
                        remoteURL: viewModel.remoteURL,
                        ocrText: viewModel.ocrText.isEmpty ? nil : viewModel.ocrText
                    )
                    if settings.clipboardBehavior == .copyOnSave {
                        ClipboardService.shared.copyImage(viewModel.renderedImage())
                    }
                    captureVM.showToast(L10n.string("Saved"))
                }
            }

            if !compact {
                GlassIconButton(
                    systemName: viewModel.isUploading ? "arrow.triangle.2.circlepath" : "link",
                    help: L10n.string("Upload and copy URL"),
                    isDisabled: settings.uploadProvider == .none
                ) {
                    Task {
                        await viewModel.upload()
                        if viewModel.remoteURL != nil {
                            captureVM.showToast(L10n.string("URL copied"))
                        } else {
                            captureVM.showToast(L10n.string("Upload failed"))
                        }
                    }
                }

                if viewModel.remoteURL != nil {
                    GlassIconButton(systemName: "trash", help: L10n.string("Delete remote")) {
                        Task { await viewModel.deleteRemote() }
                    }
                }
            }

            toolbarDivider

            GlassIconButton(systemName: "xmark", help: L10n.string("Close (Esc)")) {
                OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 8)
        .prismGlass(cornerRadius: 18)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }
}
