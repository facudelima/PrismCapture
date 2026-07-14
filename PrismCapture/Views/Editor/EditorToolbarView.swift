import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: AnnotationViewModel
    @ObservedObject var captureVM: CaptureViewModel
    @EnvironmentObject private var settings: AppSettings
    var compact: Bool = false

    private let tools: [EditorTool] = [
        .rectangle, .circle, .arrow, .line, .pencil, .highlighter,
        .blur, .pixelate, .text, .marker, .crop
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
                        help: "Grosor \(Int(width.rawValue))",
                        isSelected: viewModel.strokeWidth == width
                    ) {
                        viewModel.strokeWidth = width
                    }
                    .scaleEffect(0.55 + width.rawValue / 30)
                }

                toolbarDivider
            }

            GlassIconButton(systemName: "arrow.uturn.backward", help: "Deshacer", isDisabled: !viewModel.canUndo) {
                viewModel.undo()
            }
            GlassIconButton(systemName: "arrow.uturn.forward", help: "Rehacer", isDisabled: !viewModel.canRedo) {
                viewModel.redo()
            }

            toolbarDivider

            GlassIconButton(systemName: "doc.on.doc", help: "Copiar (⌘C)") {
                ClipboardService.shared.copyImage(viewModel.renderedImage())
                if settings.showToastOnCopy {
                    captureVM.showToast("Copiado al portapapeles")
                }
                OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
            }
            GlassIconButton(systemName: "square.and.arrow.down", help: "Guardar (⌘S)") {
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
                    captureVM.showToast("Guardado")
                }
            }

            if !compact {
                GlassIconButton(
                    systemName: viewModel.isOCRLoading ? "ellipsis" : "text.viewfinder",
                    help: "OCR"
                ) {
                    Task { await viewModel.runOCR() }
                }
                GlassIconButton(
                    systemName: viewModel.isUploading ? "arrow.triangle.2.circlepath" : "link",
                    help: "Subir y copiar URL",
                    isDisabled: settings.uploadProvider == .none
                ) {
                    Task {
                        await viewModel.upload()
                        if viewModel.remoteURL != nil {
                            captureVM.showToast("URL copiada")
                        } else {
                            captureVM.showToast("Error al subir")
                        }
                    }
                }

                if viewModel.remoteURL != nil {
                    GlassIconButton(systemName: "trash", help: "Eliminar remoto") {
                        Task { await viewModel.deleteRemote() }
                    }
                }
            }

            toolbarDivider

            GlassIconButton(systemName: "xmark", help: "Cerrar (Esc)") {
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
